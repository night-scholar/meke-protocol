// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.6;

import "../global/GlobalConfig.sol";

contract TestGlobalConfig {
    GlobalConfig public _globalConfig;

    function setUp() public {
        _globalConfig = new GlobalConfig();
    }

    function addBroker() external {
        return _globalConfig.addBroker(address(1));
    }
}
