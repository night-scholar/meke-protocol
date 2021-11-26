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

    /**
     * Match orders from one taker and multiple makers.
     *
     * @param takerOrderParam   Taker's order to match.
     * @param makerOrderParams  Array of maker's order to match with.
     * @param _perpetual        Address of perpetual contract.
     * @param amounts           Array of matching amounts of each taker/maker pair.
     */
    function matchOrders(
        LibOrder.OrderParam memory takerOrderParam,
        LibOrder.OrderParam[] memory makerOrderParams,
        address _perpetual,
        uint256[] memory amounts,
        uint256 gasFee
    ) external {
        require(globalConfig.brokers(msg.sender), "unauthorized broker");
        require(amounts.length > 0 && makerOrderParams.length == amounts.length, "no makers to match");
        require(!takerOrderParam.isMakerOnly(), "taker order is maker only");

        IPerpetual perpetual = IPerpetual(_perpetual);
        require(perpetual.status() == LibTypes.Status.NORMAL, "wrong perpetual status");

        bytes32 takerOrderHash = validateOrderParam(perpetual, takerOrderParam,"-1");
        uint256 takerFilledAmount = filled[takerOrderHash];
        if (takerFilledAmount == 0){
            claimGasFee(perpetual,takerOrderParam.trader,gasFee);
        }
        uint256 takerOpened;
        for (uint256 i = 0; i < makerOrderParams.length; i++) {
            if (amounts[i] == 0) {
                continue;
            }

            require(takerOrderParam.trader != makerOrderParams[i].trader, "self trade");
            require(takerOrderParam.isInversed() == makerOrderParams[i].isInversed(), "invalid inversed pair");
            require(takerOrderParam.isSell() != makerOrderParams[i].isSell(), "side must be long or short");
            require(!makerOrderParams[i].isMarketOrder(), "market order cannot be maker");

            validatePrice(takerOrderParam, makerOrderParams[i]);

            bytes32 makerOrderHash = validateOrderParam(perpetual, makerOrderParams[i],uint2str(i));
            uint256 makerFilledAmount = filled[makerOrderHash];
            if (makerFilledAmount == 0){
                claimGasFee(perpetual,makerOrderParams[i].trader,gasFee);
            }
            require(amounts[i] <= takerOrderParam.amount.sub(takerFilledAmount), "-1:taker overfilled");
            require(amounts[i] <= makerOrderParams[i].amount.sub(makerFilledAmount),  mergeS1AndS2ReturnString(uint2str(i),":maker overfilled"));
            require(amounts[i].mod(perpetual.getGovernance().tradingLotSize) == 0, "amount must be divisible by tradingLotSize");

            uint256 opened = fillOrder(i,perpetual, takerOrderParam, makerOrderParams[i], amounts[i]);

            takerOpened = takerOpened.add(opened);
            filled[makerOrderHash] = makerFilledAmount.add(amounts[i]);
            takerFilledAmount = takerFilledAmount.add(amounts[i]);
        }
        // update fair price 
        perpetual.setFairPrice(makerOrderParams[makerOrderParams.length-1].getPrice());

        // all trades done, check taker safe.
        if (takerOpened > 0) {
            require(perpetual.isIMSafe(takerOrderParam.trader), "-1:taker initial margin unsafe");
        } else {
            require(perpetual.isSafe(takerOrderParam.trader), "-1:taker unsafe");
        }
        require(perpetual.isSafe(msg.sender), "broker unsafe");

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

    /**
     * @dev Fill order at the maker's price, then claim trading and dev fee from both side.
     *
     * @param perpetual        Address of perpetual contract.
     * @param takerOrderParam  Taker's order to match.
     * @param makerOrderParam  Maker's order to match.
     * @param amount           Amount to fiil.
     * @return Opened position amount of taker.
     */
    function fillOrder(
        uint256 index,
        IPerpetual perpetual,
        LibOrder.OrderParam memory takerOrderParam,
        LibOrder.OrderParam memory makerOrderParam,
        uint256 amount
    ) internal returns (uint256) {
        uint256 price = makerOrderParam.getPrice();
        (uint256 takerOpened, uint256 makerOpened) = perpetual.tradePosition(
            takerOrderParam.trader,
            makerOrderParam.trader,
            takerOrderParam.side(),
            price,
            amount
        );
        // int256 referrerBonusRate = perpetual.getGovernance().referrerBonusRate;

        // int256 takerTradingFee;
        // int256 makerTradingFee;

        // check if taker is activated
        if (isActivtedReferral(takerOrderParam.trader)) {
            // taker trading fee
            int256 takerTradingFee = amount.wmul(price).toInt256().wmul(takerOrderParam.takerFeeRate());
            // referere bonus
            int256 referrerBonusRate = perpetual.getGovernance().referrerBonusRate;
            int256 bonus = takerTradingFee.wmul(referrerBonusRate);
            claimReferralBonus(perpetual, takerOrderParam.trader, bonus);
            // remaining fee to exchange
            claimTradingFee(perpetual, takerOrderParam.trader, takerTradingFee.sub(bonus));
            emit ClaimReferralBonus(referrals[takerOrderParam.trader],block.timestamp,bonus);
        } else {
            int256 takerTradingFee = amount.wmul(price).toInt256().wmul(takerOrderParam.takerFeeRate());
            claimTradingFee(perpetual, takerOrderParam.trader, takerTradingFee);
        }

        // check if maker is activated
        if (isActivtedReferral(makerOrderParam.trader)) {
            // maker trading fee
            int256 makerTradingFee = amount.wmul(price).toInt256().wmul(makerOrderParam.makerFeeRate());
            // referere bonus
            int256 referrerBonusRate = perpetual.getGovernance().referrerBonusRate;
            int256 bonus = makerTradingFee.wmul(referrerBonusRate);
            claimReferralBonus(perpetual, makerOrderParam.trader, bonus);
            // remaining fee to exchange
            claimTradingFee(perpetual, makerOrderParam.trader, makerTradingFee.sub(bonus));
            emit ClaimReferralBonus(referrals[makerOrderParam.trader],block.timestamp,bonus);
        } else {
            int256 makerTradingFee = amount.wmul(price).toInt256().wmul(makerOrderParam.makerFeeRate());
            claimTradingFee(perpetual, makerOrderParam.trader, makerTradingFee);
        }

        // dev fee
        // claimTakerDevFee(perpetual, takerOrderParam.trader, price, takerOpened, amount.sub(takerOpened));
        // claimMakerDevFee(perpetual, makerOrderParam.trader, price, makerOpened, amount.sub(makerOpened));

        if (makerOpened > 0) {
            require(perpetual.isIMSafe(makerOrderParam.trader), mergeS1AndS2ReturnString(uint2str(index),":maker initial margin unsafe"));
        } else {
            require(perpetual.isSafe(makerOrderParam.trader), mergeS1AndS2ReturnString(uint2str(index),":maker unsafe"));
        }

        emit MatchWithOrders(address(perpetual), takerOrderParam, makerOrderParam, amount);

        return takerOpened;
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
}
