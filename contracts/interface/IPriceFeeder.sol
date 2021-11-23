// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;


interface IPriceFeeder {
    function price() external view returns (uint256 lastPrice, uint256 lastTimestamp);
}
