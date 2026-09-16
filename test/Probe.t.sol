// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";

interface ILum {
    function getToken() external view returns (address);
    function getFundingAccount() external view returns (address);
    function getMaxSessionDuration() external view returns (uint128);
    function getProviderMinimumStake() external view returns (uint256);
    function getModelMinimumStake() external view returns (uint256);
    function getBidFee() external view returns (uint256);
    function getMinMaxBidPricePerSecond() external view returns (uint256, uint256);
    function getComputeBalance(uint128) external view returns (uint256);
    function totalMORSupply(uint128) external view returns (uint256);
    function getProvidersTotalClaimed() external view returns (uint256);
}

contract Probe is Test {
    ILum constant L = ILum(0x6aBE1d282f72B474E54527D93b979A4f64d3030a);
    function test_probe() public {
        vm.createSelectFork("https://base-rpc.publicnode.com");
        emit log_named_address("token", L.getToken());
        emit log_named_address("fundingAccount", L.getFundingAccount());
        emit log_named_uint("maxSessionDuration", L.getMaxSessionDuration());
        emit log_named_uint("providerMinStake", L.getProviderMinimumStake());
        emit log_named_uint("modelMinStake", L.getModelMinimumStake());
        emit log_named_uint("bidFee", L.getBidFee());
        (uint256 minP, uint256 maxP) = L.getMinMaxBidPricePerSecond();
        emit log_named_uint("bidMinPricePerSecond", minP);
        emit log_named_uint("bidMaxPricePerSecond", maxP);
        emit log_named_uint("computeBalance(now)", L.getComputeBalance(uint128(block.timestamp)));
        emit log_named_uint("totalMORSupply(now)", L.totalMORSupply(uint128(block.timestamp)));
        emit log_named_uint("providersTotalClaimed", L.getProvidersTotalClaimed());
    }
}
