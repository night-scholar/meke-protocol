// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

import "../lib/LibOrder.sol";
import "../lib/LibSignature.sol";
import "../perpetual/Perpetual.sol";


contract TestOrder {
    using LibOrder for LibOrder.OrderParam;
    using LibOrder for LibOrder.Order;
    using LibSignature for LibSignature.OrderSignature;

    function getOrder(LibOrder.OrderParam memory orderParam, address perpetual, address broker)
        public
        pure
        returns (LibOrder.Order memory order)
    {
        order = orderParam.getOrder(perpetual);
    }

    function hashOrder(LibOrder.Order memory order) public pure returns (bytes32) {
        return order.hashOrder();
    }

    function getOrderHash3(LibOrder.OrderParam memory orderParam, address perpetual, address broker)
        public
        pure
        returns (bytes32)
    {
        return orderParam.getOrderHash(perpetual);
    }

    function getOrderHash1(LibOrder.Order memory order) public pure returns (bytes32) {
        return order.getOrderHash();
    }

    function expiredAt(LibOrder.OrderParam memory orderParam) public pure returns (uint256) {
        return orderParam.expiredAt();
    }

    function isValidSignature(LibOrder.OrderParam memory orderParam, bytes32 orderHash) public pure returns (bool) {
        return orderParam.signature.isValidSignature(orderHash, orderParam.trader);
    }

    function isSell(LibOrder.OrderParam memory orderParam) public pure returns (bool) {
        return orderParam.isSell();
    }

    function getPrice(LibOrder.OrderParam memory orderParam) public pure returns (uint256) {
        return orderParam.getPrice();
    }

    function isMarketOrder(LibOrder.OrderParam memory orderParam) public pure returns (bool) {
        return orderParam.isMarketOrder();
    }

    function isMarketBuy(LibOrder.OrderParam memory orderParam) public pure returns (bool) {
        return orderParam.isMarketBuy();
    }

    function isMakerOnly(LibOrder.OrderParam memory orderParam) public pure returns (bool) {
        return orderParam.isMakerOnly();
    }

    function isInversed(LibOrder.OrderParam memory orderParam) public pure returns (bool) {
        return orderParam.isInversed();
    }

    function side(LibOrder.OrderParam memory orderParam) public pure returns (LibTypes.Side) {
        return orderParam.side();
    }

    function makerFeeRate(LibOrder.OrderParam memory orderParam) public pure returns (int256) {
        return orderParam.makerFeeRate();
    }

    function takerFeeRate(LibOrder.OrderParam memory orderParam) public pure returns (int256) {
        return orderParam.takerFeeRate();
    }

    function chainId(LibOrder.OrderParam memory orderParam) public pure returns (uint256) {
        return orderParam.chainId();
    }
}
