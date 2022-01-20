// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

import "../interface/IPerpetual.sol";

contract TestSet{
    function set(address _perpetual,uint256 price) public {
        IPerpetual perpetual = IPerpetual(_perpetual);
        perpetual.setFairPrice(price);
    }
}
