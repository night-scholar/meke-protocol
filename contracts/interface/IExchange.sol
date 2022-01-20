// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

import "../lib/LibOrder.sol";

interface IExchange {
  function matchOrders(
        LibOrder.OrderParam memory takerOrderParam,
        LibOrder.OrderParam[] memory makerOrderParams,
        address _perpetual,
        LibOrder.OrderData[] memory orderDatas,
        uint256 takerGasFee
    ) external ;
}
