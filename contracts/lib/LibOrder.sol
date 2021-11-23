// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;
pragma abicoder v2;

import "./LibEIP712.sol";
import "./LibSignature.sol";
import "./LibMath.sol";
import "./LibTypes.sol";


library LibOrder {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;

    bytes32 public constant EIP712_ORDER_TYPE = keccak256(
        abi.encodePacked(
            "Order(address trader,address broker,address perpetual,uint256 amount,uint256 price,bytes32 data)"
        )
    );

    int256 public constant FEE_RATE_BASE = 10 ** 6;

    struct Order {
        address trader;
        address broker;
        address perpetual;
        uint256 amount;
        uint256 price;
        /***
         * Data contains the following values packed into 32 bytes
         * ╔════════════════════╤═══════════════════════════════════════════════════════════╗
         * ║                    │ length(bytes)   desc                                      ║
         * ╟────────────────────┼───────────────────────────────────────────────────────────╢
         * ║ version            │ 1               order version                             ║
         * ║ side               │ 1               0: buy (long), 1: sell (short)            ║
         * ║ isMarketOrder      │ 1               0: limitOrder, 1: marketOrder             ║
         * ║ expiredAt          │ 5               order expiration time in seconds          ║
         * ║ asMakerFeeRate     │ 2               maker fee rate (base 100,000)             ║
         * ║ asTakerFeeRate     │ 2               taker fee rate (base 100,000)             ║
         * ║ salt               │ 8               salt                                      ║
         * ║ isMakerOnly        │ 1               is maker only                             ║
         * ║ isInversed         │ 1               is inversed contract                      ║
         * ║ chainId            │ 8               chain id                                  ║
         * ╚════════════════════╧═══════════════════════════════════════════════════════════╝
         */
        bytes32 data;
    }

    struct OrderParam {
        address trader;
        uint256 amount;
        uint256 price;
        bytes32 data;
        LibSignature.OrderSignature signature;
    }

    /**
     * @dev Get order hash from parameters of order. Rebuild order and hash it.
     *
     * @param orderParam Order parameters.
     * @param perpetual  Address of perpetual contract.
     * @return orderHash Hash of the order.
     */
    function getOrderHash(
        OrderParam memory orderParam,
        address perpetual
    ) internal pure returns (bytes32 orderHash) {
        Order memory order = getOrder(orderParam, perpetual);
        orderHash = LibEIP712.hashEIP712Message(hashOrder(order));
    }

    /**
     * @dev Get order hash from order.
     *
     * @param order Order to hash.
     * @return orderHash Hash of the order.
     */
    function getOrderHash(Order memory order) internal pure returns (bytes32 orderHash) {
        orderHash = LibEIP712.hashEIP712Message(hashOrder(order));
    }

    /**
     * @dev Get order from parameters.
     *
     * @param orderParam Order parameters.
     * @param perpetual  Address of perpetual contract.
     * @return order Order data structure.
     */
    function getOrder(
        OrderParam memory orderParam,
        address perpetual
    ) internal pure returns (LibOrder.Order memory order) {
        order.trader = orderParam.trader;
        order.perpetual = perpetual;
        order.amount = orderParam.amount;
        order.price = orderParam.price;
        order.data = orderParam.data;
    }

    /**
     * @dev Hash fields in order to generate a hash as identifier.
     *
     * @param order Order to hash.
     * @return result Hash of the order.
     */
    function hashOrder(Order memory order) internal pure returns (bytes32 result) {
        bytes32 orderType = EIP712_ORDER_TYPE;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            // "Order(address trader,address broker,address perpetual,uint256 amount,uint256 price,bytes32 data)"
            // hash these 6 field to get a hash
            // address will be extended to 32 bytes.
            let start := sub(order, 32)
            let tmp := mload(start)
            mstore(start, orderType)
            // [0...32)   bytes: EIP712_ORDER_TYPE, len 32
            // [32...224) bytes: order, len 6 * 32
            // 224 = 32 + 192
            result := keccak256(start, 224)
            mstore(start, tmp)
        }
    }

    // extract order parameters.

    function orderVersion(OrderParam memory orderParam) internal pure returns (uint256) {
        return uint256(uint8(bytes1(orderParam.data)));
    }

    function expiredAt(OrderParam memory orderParam) internal pure returns (uint256) {
        return uint256(uint40(bytes5(orderParam.data << (8 * 3))));
    }

    function isSell(OrderParam memory orderParam) internal pure returns (bool) {
        bool sell = uint8(orderParam.data[1]) == 1;
        return isInversed(orderParam) ? !sell : sell;
    }

    function getPrice(OrderParam memory orderParam) internal pure returns (uint256) {
        return isInversed(orderParam) ? LibMathUnsigned.WAD().wdiv(orderParam.price) : orderParam.price;
    }

    function isMarketOrder(OrderParam memory orderParam) internal pure returns (bool) {
        return uint8(orderParam.data[2]) > 0;
    }

    function isMarketBuy(OrderParam memory orderParam) internal pure returns (bool) {
        return !isSell(orderParam) && isMarketOrder(orderParam);
    }

    function isMakerOnly(OrderParam memory orderParam) internal pure returns (bool) {
        return uint8(orderParam.data[22]) > 0;
    }

    function isInversed(OrderParam memory orderParam) internal pure returns (bool) {
        return uint8(orderParam.data[23]) > 0;
    }

    function side(OrderParam memory orderParam) internal pure returns (LibTypes.Side) {
        return isSell(orderParam) ? LibTypes.Side.SHORT : LibTypes.Side.LONG;
    }

    function makerFeeRate(OrderParam memory orderParam) internal pure returns (int256) {
        return int256(int16(bytes2(orderParam.data << (8 * 8)))).mul(LibMathSigned.WAD()).div(FEE_RATE_BASE);
    }

    function takerFeeRate(OrderParam memory orderParam) internal pure returns (int256) {
        return int256(int16(bytes2(orderParam.data << (8 * 10)))).mul(LibMathSigned.WAD()).div(FEE_RATE_BASE);
    }

    function chainId(OrderParam memory orderParam) internal pure returns (uint256) {
        return uint256(uint64(bytes8(orderParam.data << (8 * 24))));
    }
}
