// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
library LibSD {
    struct SD { int64 mean; int64 sqSum; }
    function add(SD storage self, int64 x_, int64 c_) internal { int64 om=self.mean; self.mean=self.mean+(x_-self.mean)/c_; self.sqSum=self.sqSum+(x_-self.mean)*(x_-om); }
    function remove(SD storage self, int64 x_, int64 c_) internal {
        if (c_==0){ self.mean=0; self.sqSum=0; return; }
        int64 om=self.mean; self.mean=self.mean-(x_-self.mean)/c_; self.sqSum=self.sqSum-(x_-self.mean)*(x_-om);
    }
}
contract Wrap { using LibSD for LibSD.SD; LibSD.SD public s;
    function add(int64 x,int64 c) external { s.add(x,c);} function remove(int64 x,int64 c) external { s.remove(x,c);}
    function get() external view returns(int64,int64){return(s.mean,s.sqSum);} }

contract LibSDremove is Test {
    Wrap w; int64 constant XMAX=2147483647; int64 constant IMIN=-9223372036854775808;
    function setUp() public { w=new Wrap(); }
    function _tryR(int64 x,int64 c) internal returns(bool){ try w.remove(x,c){return true;}catch{return false;} }
    function _tryA(int64 x,int64 c) internal returns(bool){ try w.add(x,c){return true;}catch{return false;} }

    // Can an attacker drive sqSum toward int64 MIN via remove so a victim's later op underflows -> revert?
    function test_remove_underflow_brick() public {
        // build up sqSum positive first (like existing model), then remove huge terms to push toward IMIN
        _tryA(XMAX,1); _tryA(-XMAX,2); // sqSum ~ +9.22e18
        (,int64 sq0)=w.get(); emit log_named_int("sqSum after adds", sq0);
        // remove with extreme x subtracts (x-newMean)(x-oldMean); craft to drive sqSum negative
        int64 c=2;
        for(uint i=0;i<10;i++){
            c++; bool ok=_tryR(i%2==0?XMAX:-XMAX, c);
            (int64 m,int64 sq)=w.get();
            emit log_named_int("iter", int256(i)); emit log_named_int("  sqSum", sq); emit log_named_int("  ok", ok?int256(1):int256(0));
            if(!ok){ emit log("remove REVERTED (underflow) -> would brick closeSession"); break; }
        }
    }
}
