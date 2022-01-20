// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../interface/IPriceFeeder.sol";
import "../interface/IExchange.sol";


contract Broker{
    IPriceFeeder public priceFeeder ;
    IExchange public exchange ;
    uint256 public gasUsed;
    uint256 public timestamp;
    uint256 public price;
    constructor(address _chainlink,address _exchange){
        priceFeeder = IPriceFeeder(_chainlink);
        exchange = IExchange(_exchange);
    }
    function batchMatchOrders(
        LibOrder.OrderParam memory takerOrderParam,
        LibOrder.OrderParam[] memory makerOrderParams,
        address _perpetual,
        LibOrder.OrderData[] memory orderDatas,
        uint256 takerGasFee
    ) external{
        uint256 gasStart = gasleft();
        exchange.matchOrders(
            takerOrderParam,
            makerOrderParams,
            _perpetual,
            orderDatas,
            takerGasFee
        );
        gasUsed = gasStart - gasleft();
    }
}