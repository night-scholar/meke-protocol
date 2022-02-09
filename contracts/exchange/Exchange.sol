// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

import "../lib/LibMath.sol";
import "../lib/LibOrder.sol";
import "../lib/LibSignature.sol";
import "../interface/IGlobalConfig.sol";
import "../interface/IPerpetual.sol";

contract Exchange {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;
    using LibOrder for LibOrder.Order;
    using LibOrder for LibOrder.OrderParam;
    using LibSignature for LibSignature.OrderSignature;

    // to verify the field in order data, increase if there are incompatible update in order's data.
    uint256 public constant SUPPORTED_ORDER_VERSION = 2;
    IGlobalConfig public globalConfig;

    // referrals
    mapping(address => address) public referrals;

    // order status
    mapping(bytes32 => uint256) public filled;
    mapping(bytes32 => bool) public cancelled;
    
    event MatchWithOrders(
        address perpetual,
        LibOrder.OrderParam takerOrderParam,
        LibOrder.OrderParam makerOrderParam,
        uint256 amount
    );
    event Cancel(bytes32 indexed orderHash);
    event ActivateReferral(address indexed referrer, address indexed referree);
    event ClaimReferralBonus(address indexed referrer,uint256,int256);

    constructor(address _globalConfig) {
        globalConfig = IGlobalConfig(_globalConfig);
    }

    // /**
    //  * Match orders from one taker and multiple makers.
    //  *
    //  * @param takerOrderParam   Taker's order to match.
    //  * @param makerOrderParams  Array of maker's order to match with.
    //  * @param _perpetual        Address of perpetual contract.
    //  * @param amounts           Array of matching amounts of each taker/maker pair.
    //  */
    function matchOrders(
        LibOrder.OrderParam memory takerOrderParam,
        LibOrder.OrderParam[] memory makerOrderParams,
        address _perpetual,
        LibOrder.OrderData[] memory orderDatas,
        uint256 takerGasFee
    ) external {
        require(globalConfig.brokers(msg.sender), "unauthorized broker");
        // require(dwgAmounts.length > 1 && makerOrderParams.length == dwgAmounts.length-1, "no makers to match");
        require(!takerOrderParam.isMakerOnly(), "taker order is maker only");

        IPerpetual perpetual = IPerpetual(_perpetual);
        require(perpetual.status() == LibTypes.Status.NORMAL, "wrong perpetual status");

        bytes32 takerOrderHash = validateOrderParam(perpetual, takerOrderParam,"-1");
        uint256 takerFilledAmount = filled[takerOrderHash];

        if (takerFilledAmount != 0){
            takerGasFee = 0;
        }
        uint256 takerOpened;
        
        for (uint256 i = 0; i < makerOrderParams.length; i++) {
            if (orderDatas[i].amount == 0) {
                continue;
            }

            require(takerOrderParam.trader != makerOrderParams[i].trader, "self trade");
            require(takerOrderParam.isInversed() == makerOrderParams[i].isInversed(), "invalid inversed pair");
            require(takerOrderParam.isSell() != makerOrderParams[i].isSell(), "side must be long or short");
            require(!makerOrderParams[i].isMarketOrder(), "market order cannot be maker");

            validatePrice(takerOrderParam, makerOrderParams[i]);

            bytes32 makerOrderHash = validateOrderParam(perpetual, makerOrderParams[i],uint2str(i));
            uint256 makerFilledAmount = filled[makerOrderHash];
            if (makerFilledAmount != 0){
                orderDatas[i].gasFee = 0;
            }

            require(orderDatas[i].amount <= takerOrderParam.amount.sub(takerFilledAmount), "-1:taker overfilled");
            require(orderDatas[i].amount <= makerOrderParams[i].amount.sub(makerFilledAmount),  mergeS1AndS2ReturnString(uint2str(i),":maker overfilled"));
            require(orderDatas[i].amount.mod(perpetual.getGovernance().tradingLotSize) == 0, "amount must be divisible by tradingLotSize");

            uint256 opened = fillOrder(perpetual, takerOrderParam, makerOrderParams[i], orderDatas[i],takerGasFee);

            takerOpened = takerOpened.add(opened);
            filled[makerOrderHash] = makerFilledAmount.add(orderDatas[i].amount);
            takerFilledAmount = takerFilledAmount.add(orderDatas[i].amount);
            emit MatchWithOrders(_perpetual,takerOrderParam,makerOrderParams[i],orderDatas[i].amount);
        }
        // update fair price 
        perpetual.setFairPrice(makerOrderParams[makerOrderParams.length-1].getPrice());

        // all trades done, check taker safe.
        require(perpetual.isSafe(takerOrderParam.trader), "-1:taker unsafe");
        // if (takerOpened > 0) {
        //     // require(perpetual.isIMSafe(takerOrderParam.trader), "-1:taker initial margin unsafe");
        // } else {
        //     require(perpetual.isSafe(takerOrderParam.trader), "-1:taker unsafe");
        // }
        // require(perpetual.isSafe(msg.sender), "broker unsafe");

        filled[takerOrderHash] = takerFilledAmount;
    }

    /**
     * @dev Cancel order.
     *
     * @param order Order to cancel.
     */
    function cancelOrder(LibOrder.Order memory order) public {
        require(msg.sender == order.trader || msg.sender == order.broker, "invalid caller");

        bytes32 orderHash = order.getOrderHash();
        cancelled[orderHash] = true;

        emit Cancel(orderHash);
    }

    /**
     * activate referral relationship
     */
    function activateReferral(address referral) external {
        require(msg.sender != referral, "refer self");
        require(referrals[msg.sender] == address(0), "already activated");
        referrals[msg.sender] = referral;
        emit ActivateReferral(referral, msg.sender);
    }

    /**
     * check if trader has activated for this perpetual market
     */
    function getReferral(address trader) internal view returns (address) {
        return referrals[trader];
    }

    function isActivtedReferral(address trader) internal view returns (bool) {
        return referrals[trader] != address(0);
    }


    /**
     * @dev Get current chain id. need istanbul hardfork.
     *
     * @return id Current chain id.
     */
    function getChainId() public pure returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }

    // /**
    //  * @dev Fill order at the maker's price, then claim trading and dev fee from both side.
    //  *
    //  * @param perpetual        Address of perpetual contract.
    //  * @param takerOrderParam  Taker's order to match.
    //  * @param makerOrderParam  Maker's order to match.
    //  * @param amount           Amount to fiil.
    //  * @return Opened position amount of taker.
    //  */
    function fillOrder(
        IPerpetual perpetual,
        LibOrder.OrderParam memory takerOrderParam,
        LibOrder.OrderParam memory makerOrderParam,
        LibOrder.OrderData memory orderData,
        uint256 takerGasFee
    ) internal returns (uint256) {
        uint256 price = makerOrderParam.getPrice();
        
        (LibOrder.TradeData memory tradeData) = perpetual.tradePosition(
            takerOrderParam.trader,
            makerOrderParam.trader,
            takerOrderParam.side(),
            price,
            orderData.amount
        );  

        int256 takerTradingFee = orderData.amount.wmul(price).toInt256().wmul(takerOrderParam.takerFeeRate());
        int256 makerTradingFee = orderData.amount.wmul(price).toInt256().wmul(makerOrderParam.makerFeeRate());
        
        dealOrderData(takerOrderParam.trader,perpetual,takerTradingFee.add(takerGasFee.toInt256()),tradeData.takerOpened,tradeData.takerClosed,tradeData.takerOriginalSize,price,orderData.takerLeverage);
        dealOrderData(makerOrderParam.trader,perpetual,makerTradingFee.add(orderData.gasFee.toInt256()),tradeData.makerOpened,tradeData.makerClosed,tradeData.makerOriginalSize,price,orderData.makerLeverage);
       
        claimGasFee(perpetual,takerOrderParam.trader,takerGasFee);
        claimGasFee(perpetual,makerOrderParam.trader,orderData.gasFee);
        // check if taker is activated
        if (isActivtedReferral(takerOrderParam.trader)) {
            // referere bonus
            int256 referrerBonusRate = perpetual.getGovernance().referrerBonusRate;
            int256 bonus = takerTradingFee.wmul(referrerBonusRate);
            claimReferralBonus(perpetual, takerOrderParam.trader, bonus);
            // remaining fee to exchange
            claimTradingFee(perpetual, takerOrderParam.trader, takerTradingFee.sub(bonus));
            emit ClaimReferralBonus(referrals[takerOrderParam.trader],block.timestamp,bonus);
        } else {
            claimTradingFee(perpetual, takerOrderParam.trader, takerTradingFee);
        }

        // check if maker is activated
        if (isActivtedReferral(makerOrderParam.trader)) {
            // referere bonus
            int256 referrerBonusRate = perpetual.getGovernance().referrerBonusRate;
            int256 bonus = makerTradingFee.wmul(referrerBonusRate);
            claimReferralBonus(perpetual, makerOrderParam.trader, bonus);
            // remaining fee to exchange
            claimTradingFee(perpetual, makerOrderParam.trader, makerTradingFee.sub(bonus));
            emit ClaimReferralBonus(referrals[makerOrderParam.trader],block.timestamp,bonus);
        } else {
            claimTradingFee(perpetual, makerOrderParam.trader, makerTradingFee);
        }


        require(perpetual.isSafe(makerOrderParam.trader), mergeS1AndS2ReturnString(uint2str(orderData.index),":maker unsafe"));
       
        // if (tradeData.makerOpened > 0) {
        //     // require(perpetual.isIMSafe(makerOrderParam.trader), mergeS1AndS2ReturnString(uint2str(orderData.index),":maker initial margin unsafe"));
        // } else {
        //     require(perpetual.isSafe(makerOrderParam.trader), mergeS1AndS2ReturnString(uint2str(orderData.index),":maker unsafe"));
        // }

        emit MatchWithOrders(address(perpetual), takerOrderParam, makerOrderParam, orderData.amount);

        return tradeData.takerOpened;
    }
    /**
     * @dev Check prices are meet.
     *
     * @param takerOrderParam  Taker's order.
     * @param takerOrderParam  Maker's order.
     */
    function validatePrice(LibOrder.OrderParam memory takerOrderParam, LibOrder.OrderParam memory makerOrderParam)
        internal
        pure
    {
        if (takerOrderParam.isMarketOrder()) {
            return;
        }
        uint256 takerPrice = takerOrderParam.getPrice();
        uint256 makerPrice = makerOrderParam.getPrice();
        require(takerOrderParam.isSell() ? takerPrice <= makerPrice : takerPrice >= makerPrice, "price not match");
    }


    /**
     * @dev Validate fields of order.
     *
     * @param perpetual  Instance of perpetual contract.
     * @param orderParam Order parameter.
     * @return orderHash Valid order hash.
     */
    function validateOrderParam(IPerpetual perpetual, LibOrder.OrderParam memory orderParam,string memory index)
        internal
        view
        returns (bytes32)
    {
        require(orderParam.orderVersion() == SUPPORTED_ORDER_VERSION, mergeS1AndS2ReturnString(index,":unsupported version"));
        require(orderParam.expiredAt() >= block.timestamp, mergeS1AndS2ReturnString(index,":order expired"));
        require(orderParam.chainId() == getChainId(), mergeS1AndS2ReturnString(index,":unmatched chainid"));

        bytes32 orderHash = orderParam.getOrderHash(address(perpetual));
        require(!cancelled[orderHash], mergeS1AndS2ReturnString(index,":cancelled order"));
        require(orderParam.signature.isValidSignature(orderHash, orderParam.trader), mergeS1AndS2ReturnString(index,":invalid signature"));
        require(filled[orderHash] < orderParam.amount, mergeS1AndS2ReturnString(index,":fullfilled order"));

        return orderHash;
    }

    /**
     * @dev Claim trading fee. Fee goes to brokers margin account.
     *
     * @param perpetual Address of perpetual contract.
     * @param trader    Address of account who will pay fee out.
     * @param fee       Amount of fee, decimals = 18.
     */
    function claimTradingFee(
        IPerpetual perpetual,
        address trader,
        int256 fee
    )
        internal
    {
        if (fee > 0) {
            perpetual.transferCashBalance(trader, msg.sender, fee.toUint256());
        } else if (fee < 0) {
            perpetual.transferCashBalance(msg.sender, trader, fee.neg().toUint256());
        }
    }
    

    function claimGasFee(
        IPerpetual perpetual,
        address trader,
        uint256 fee
    )
        internal
    {
        if (fee > 0) {
            perpetual.transferCashBalance(trader, msg.sender, fee);
        } else if (fee < 0) {
            perpetual.transferCashBalance(msg.sender, trader, fee);
        }
    }

   /**
    * clac referral bonus
    */
    function claimReferralBonus(
        IPerpetual perpetual,
        address trader,
        int256 fee
    )
        internal
    {
        address referral = getReferral(trader);
        if (referral != address(0) && fee > 0) {
            perpetual.transferCashBalance(trader, referral, fee.toUint256());
        }
    }

    /**
     * @dev Claim dev fee. Especially, for fee from closing positon
     *
     * @param perpetual     Address of perpetual.
     * @param trader        Address of margin account.
     * @param price         Price of position.
     * @param openedAmount  Opened position amount.
     * @param closedAmount  Closed position amount.
     * @param feeRate       Maker's order.
     */
    function claimDevFee(
        IPerpetual perpetual,
        address trader,
        uint256 price,
        uint256 openedAmount,
        uint256 closedAmount,
        int256 feeRate
    )
        internal
    {
        if (feeRate == 0) {
            return;
        }
        int256 hard = price.wmul(openedAmount).toInt256().wmul(feeRate);
        int256 soft = price.wmul(closedAmount).toInt256().wmul(feeRate);
        int256 fee = hard.add(soft);
        address devAddress = perpetual.devAddress();
        if (fee > 0) {
            int256 available = perpetual.availableMargin(trader);
            require(available >= hard, "available margin too low for fee");
            fee = fee.min(available);
            perpetual.transferCashBalance(trader, devAddress, fee.toUint256());
        } else if (fee < 0) {
            perpetual.transferCashBalance(devAddress, trader, fee.neg().toUint256());
            require(perpetual.isSafe(devAddress), "dev unsafe");
        }
    }

    /**
     * @dev Claim dev fee in taker fee rate set by perpetual governacne.
     *
     * @param perpetual     Address of perpetual.
     * @param trader        Taker's order.
     * @param price         Maker's order.
     * @param openedAmount  Maker's order.
     * @param closedAmount  Maker's order.
     */
    function claimTakerDevFee(
        IPerpetual perpetual,
        address trader,
        uint256 price,
        uint256 openedAmount,
        uint256 closedAmount
    )
        internal
    {
        int256 rate = perpetual.getGovernance().takerDevFeeRate;
        claimDevFee(perpetual, trader, price, openedAmount, closedAmount, rate);
    }

    /**
     * @dev Claim dev fee in maker fee rate set by perpetual governacne.
     *
     * @param perpetual     Address of perpetual.
     * @param trader        Taker's order.
     * @param price         Maker's order.
     * @param openedAmount  Maker's order.
     * @param closedAmount  Maker's order.
     */
    function claimMakerDevFee(
        IPerpetual perpetual,
        address trader,
        uint256 price,
        uint256 openedAmount,
        uint256 closedAmount
    )
        internal
    {
        int256 rate = perpetual.getGovernance().makerDevFeeRate;
        claimDevFee(perpetual, trader, price, openedAmount, closedAmount, rate);
    }

    function dealOrderData(address trader,IPerpetual perpetual,int256 fee,uint256 opened,uint256 closed,uint256 originalSize, uint256 price,uint256 leverage) internal {
        int256 traderMarginBalance = perpetual.marginBalance(trader);
        int256 traderMinimumBalance;

        if (opened > 0){
            if (closed > 0){
                //revert position
                traderMinimumBalance = opened.wmul(price).wdiv(leverage).toInt256().add(fee);
            }else {
                //add position
                traderMinimumBalance = traderMarginBalance.add(opened.wmul(price).wdiv(leverage).toInt256()).add(fee);
            }
        }else{
            //sub position
            traderMinimumBalance = (originalSize.sub(closed)).wdiv(originalSize).wmul(traderMarginBalance.toUint256()).toInt256().add(fee);
        }

        if (traderMarginBalance > traderMinimumBalance){
            perpetual.withdrawFor(payable(trader), (traderMarginBalance.sub(traderMinimumBalance)).div(perpetual.scaler()).toUint256());
        }else if (traderMarginBalance < traderMinimumBalance){
            perpetual.depositFor(trader, (traderMinimumBalance.sub(traderMarginBalance)).div(perpetual.scaler()).toUint256());
        }
    }

    function mergeS1AndS2ReturnString(string memory s1,string memory s2) pure internal returns(string memory) {
        return string(abi.encodePacked(s1, s2));
    }
       
    function uint2str(uint _i) pure internal returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len - 1;
        while (_i != 0) {
            bstr[k--] = byte(uint8(48 + _i % 10));
            _i /= 10;
        }
        return string(bstr);
    }


    function toAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2*i] = char(hi);
            s[2*i+1] = char(lo);            
        }
        return string(s);
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
