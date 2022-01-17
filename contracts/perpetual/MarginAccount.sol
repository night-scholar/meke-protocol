// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;
pragma abicoder v2;

import  "../lib/LibMath.sol";
import "../lib/LibTypes.sol";
import "./Collateral.sol";

contract MarginAccount is Collateral {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;
    using LibTypes for LibTypes.Side;

    event UpdatePositionAccount(
        address indexed trader,
        LibTypes.MarginAccount account,
        uint256 perpetualTotalSize,
        uint256 price
    );
    event UpdateInsuranceFund(int256 newVal);
    event Transfer(address indexed from, address indexed to, int256 wadAmount, int256 balanceFrom, int256 balanceTo);
    event InternalUpdateBalance(address indexed trader, int256 wadAmount, int256 balance);

    constructor(address _globalConfig, address _collateral, uint256 _collateralDecimals)
        Collateral(_globalConfig, _collateral, _collateralDecimals)
    {}

    /**
      * @dev Calculate max amount can be liquidated to trader's acccount.
      *
      * @param trader           Address of account owner.
      * @param liquidationPrice Markprice used in calculation.
      * @return Max liquidatable amount, note this amount is not aligned to lotSize.
      */
    function calculateLiquidateAmount(address trader, uint256 liquidationPrice) public returns (uint256) {
        // if (marginAccounts[trader].size == 0) {
        //     return 0;
        // }
        if (marginAccounts[trader].side == LibTypes.Side.FLAT||marginAccounts[trader].side == LibTypes.Side.EMPTY){
            return 0;
        }
        LibTypes.MarginAccount memory account = marginAccounts[trader];
        int256 liquidationAmount = account.cashBalance.add(account.entrySocialLoss);
        liquidationAmount = liquidationAmount
            .sub(marginWithPrice(trader, liquidationPrice).toInt256())
            .sub(socialLossPerContract(account.side).wmul(account.size.toInt256()));
        int256 tmp = account.entryValue.toInt256()
            .sub(account.entryFundingLoss)
            .add(fundingModule.currentAccumulatedFundingPerContract().wmul(account.size.toInt256()))
            .sub(account.size.wmul(liquidationPrice).toInt256());
        if (account.side == LibTypes.Side.LONG) {
            liquidationAmount = liquidationAmount.sub(tmp);
        } else if (account.side == LibTypes.Side.SHORT) {
            liquidationAmount = liquidationAmount.add(tmp);
        } else {
            return 0;
        }
        int256 denominator = governance.liquidationPenaltyRate
            .add(governance.penaltyFundRate).toInt256()
            .sub(governance.initialMarginRate.toInt256())
            .wmul(liquidationPrice.toInt256());
        liquidationAmount = liquidationAmount.wdiv(denominator);
        liquidationAmount = liquidationAmount.max(0);
        liquidationAmount = liquidationAmount.min(account.size.toInt256());
        return liquidationAmount.toUint256();
    }

    /**
      * @dev Calculate pnl of an margin account at trade price for given amount.
      *
      * @param account    Account of account owner.
      * @param tradePrice Price used in calculation.
      * @param amount     Amount used in calculation.
      * @return PNL of given account.
      */
    function calculatePnl(LibTypes.MarginAccount memory account, uint256 tradePrice, uint256 amount)
        internal
        returns (int256)
    {
        // if (account.size == 0) {
        //     return 0;
        // }
        if (account.side == LibTypes.Side.FLAT||account.side == LibTypes.Side.EMPTY){
            return 0;
        }
        int256 p1 = tradePrice.wmul(amount).toInt256();
        int256 p2;
        if (amount == account.size) {
            p2 = account.entryValue.toInt256();
        } else {
            // p2 = account.entryValue.wmul(amount).wdiv(account.size).toInt256();
            p2 = account.entryValue.wfrac(amount, account.size).toInt256();
        }
        int256 profit = account.side == LibTypes.Side.LONG ? p1.sub(p2) : p2.sub(p1);
        // prec error
        if (profit != 0) {
            profit = profit.sub(1);
        }
        int256 loss1 = socialLossWithAmount(account, amount);
        int256 loss2 = fundingLossWithAmount(account, amount);
        return profit.sub(loss1).sub(loss2);
    }

    /**
      * @dev Calculate margin balance at given mark price:
      *         margin balance = cash balance + pnl
      *
      * @param trader    Address of account owner.
      * @param markPrice Price used in calculation.
      * @return Value of margin balance.
      */
    function marginBalanceWithPrice(address trader, uint256 markPrice) internal returns (int256) {
        return marginAccounts[trader].cashBalance.add(pnlWithPrice(trader, markPrice));
    }

    /**
      * @dev Calculate (initial) margin value with initial margin rate at given mark price:
      *         margin taken by positon = value of positon * initial margin rate.
      *
      * @param trader    Address of account owner.
      * @param markPrice Price used in calculation.
      * @return Value of margin.
      */
    function marginWithPrice(address trader, uint256 markPrice) internal view returns (uint256) {
        if (marginAccounts[trader].side == LibTypes.Side.EMPTY){
            return 0;
        }
        return marginAccounts[trader].size.wmul(markPrice).wmul(governance.initialMarginRate);
    }

    /**
      * @dev Calculate maintenance margin value with maintenance margin rate at given mark price:
      *         maintenance margin taken by positon = value of positon * maintenance margin rate.
      *         maintenance margin must be lower than (initial) margin (see above)
      *
      * @param trader    Address of account owner.
      * @param markPrice Price used in calculation.
      * @return Value of margin.
      */
    function maintenanceMarginWithPrice(address trader, uint256 markPrice) internal view returns (uint256) {
        if (marginAccounts[trader].side == LibTypes.Side.EMPTY){
            return 0;
        }
        return marginAccounts[trader].size.wmul(markPrice).wmul(governance.maintenanceMarginRate);
    }

    /**
      * @dev Calculate available margin balance, which can be used to open new positions, at given mark price:
      *      An available margin could be negative:
      *         avaiable margin balance = margin balance - margin taken by position
      *
      * @param trader    Address of account owner.
      * @param markPrice Price used in calculation.
      * @return Value of available margin balance.
      */
    function availableMarginWithPrice(address trader, uint256 markPrice) internal returns (int256) {
        int256 marginBalance = marginBalanceWithPrice(trader, markPrice);
        int256 margin = marginWithPrice(trader, markPrice).toInt256();
        return marginBalance.sub(margin);
    }


    /**
      * @dev Calculate pnl (profit and loss) of a margin account at given mark price.
      *
      * @param trader    Address of account owner.
      * @param markPrice Price used in calculation.
      * @return Value of available margin balance.
      */
    function pnlWithPrice(address trader, uint256 markPrice) internal returns (int256) {
        LibTypes.MarginAccount memory account = marginAccounts[trader];
        return calculatePnl(account, markPrice, account.size);
    }

    // Internal functions
    function increaseTotalSize(LibTypes.Side side, uint256 amount) internal {
        totalSizes[uint256(side)] = totalSizes[uint256(side)].add(amount);
    }

    function decreaseTotalSize(LibTypes.Side side, uint256 amount) internal {
        totalSizes[uint256(side)] = totalSizes[uint256(side)].sub(amount);
    }

    function socialLoss(LibTypes.MarginAccount memory account) internal view returns (int256) {
        return socialLossWithAmount(account, account.size);
    }

    function socialLossWithAmount(LibTypes.MarginAccount memory account, uint256 amount)
        internal
        view
        returns (int256)
    {
        if (account.side == LibTypes.Side.EMPTY||account.side == LibTypes.Side.FLAT) {
            return 0;
        }
        int256 loss = socialLossPerContract(account.side).wmul(amount.toInt256());
        if (amount == account.size) {
            loss = loss.sub(account.entrySocialLoss);
        } else {
            // loss = loss.sub(account.entrySocialLoss.wmul(amount).wdiv(account.size));
            loss = loss.sub(account.entrySocialLoss.wfrac(amount.toInt256(), account.size.toInt256()));
            // prec error
            if (loss != 0) {
                loss = loss.add(1);
            }
        }
        return loss;
    }

    function fundingLoss(LibTypes.MarginAccount memory account) internal returns (int256) {
        return fundingLossWithAmount(account, account.size);
    }

    function fundingLossWithAmount(LibTypes.MarginAccount memory account, uint256 amount) internal returns (int256) {
        if (account.side == LibTypes.Side.FLAT||account.side == LibTypes.Side.EMPTY) {
            return 0;
        }
        int256 loss = fundingModule.currentAccumulatedFundingPerContract().wmul(amount.toInt256());
        if (amount == account.size) {
            loss = loss.sub(account.entryFundingLoss);
        } else {
            // loss = loss.sub(account.entryFundingLoss.wmul(amount.toInt256()).wdiv(account.size.toInt256()));
            loss = loss.sub(account.entryFundingLoss.wfrac(amount.toInt256(), account.size.toInt256()));
        }
        if (account.side == LibTypes.Side.SHORT) {
            loss = loss.neg();
        }
        if (loss != 0 && amount != account.size) {
            loss = loss.add(1);
        }
        return loss;
    }

    /**
      * @dev Recalculate cash balance of a margin account and update the storage.
      *
      * @param trader    Address of account owner.
      * @param markPrice Price used in calculation.
      */
    function remargin(address trader, uint256 markPrice) internal {
        LibTypes.MarginAccount storage account = marginAccounts[trader];
        // if (account.size == 0) {
        //     return;
        // }
        if (account.side == LibTypes.Side.FLAT||account.side == LibTypes.Side.EMPTY){
            return;
        }
        int256 rpnl = calculatePnl(account, markPrice, account.size);
        account.cashBalance = account.cashBalance.add(rpnl);
        account.entryValue = markPrice.wmul(account.size);
        account.entrySocialLoss = socialLossPerContract(account.side).wmul(account.size.toInt256());
        account.entryFundingLoss = fundingModule.currentAccumulatedFundingPerContract().wmul(account.size.toInt256());
        emit UpdatePositionAccount(trader, account, totalSize(account.side), markPrice);
    }

    /**
      * @dev Open new position for a margin account.
      *
      * @param account Account of account owner.
      * @param side    Side of position to open.
      * @param price   Price of position to open.
      * @param amount  Amount of position to open.
      */
    function open(LibTypes.MarginAccount memory account, LibTypes.Side side, uint256 price, uint256 amount) internal {
        require(amount > 0, "open: invald amount");
        if (account.side == LibTypes.Side.EMPTY) {
            account.side = side;
            account.size = amount;
            account.entryValue = price.wmul(amount);
            account.entrySocialLoss = socialLossPerContract(side).wmul(amount.toInt256());
            account.entryFundingLoss = fundingModule.currentAccumulatedFundingPerContract().wmul(amount.toInt256());
        }else{
            account.size = account.size.add(amount);
            account.entryValue = account.entryValue.add(price.wmul(amount));
            account.entrySocialLoss = account.entrySocialLoss.add(socialLossPerContract(side).wmul(amount.toInt256()));
            account.entryFundingLoss = account.entryFundingLoss.add(
                fundingModule.currentAccumulatedFundingPerContract().wmul(amount.toInt256())
            );
        }
        increaseTotalSize(side, amount);
        // require(amount > 0, "open: invald amount");
        // if (account.size == 0) {
        //     account.side = side;
        // }
        // account.size = account.size.add(amount);
        // account.entryValue = account.entryValue.add(price.wmul(amount));
        // account.entrySocialLoss = account.entrySocialLoss.add(socialLossPerContract(side).wmul(amount.toInt256()));
        // account.entryFundingLoss = account.entryFundingLoss.add(
        //     fundingModule.currentAccumulatedFundingPerContract().wmul(amount.toInt256())
        // );
        // increaseTotalSize(side, amount);
    }

    /**
      * @dev CLose position for a margin account, get collateral back.
      *
      * @param account Account of account owner.
      * @param price   Price of position to close.
      * @param amount  Amount of position to close.
      */
    function close(LibTypes.MarginAccount memory account, uint256 price, uint256 amount) internal returns (int256) {
        int256 rpnl = calculatePnl(account, price, amount);
        if (account.size == amount){
            account.cashBalance = account.cashBalance.add(rpnl);
            account.entrySocialLoss = flatAmount.toInt256();
            account.entryFundingLoss = flatAmount.toInt256();
            account.entryValue = flatAmount;
            account.size = flatAmount;
            decreaseTotalSize(account.side, amount);
            account.side = LibTypes.Side.EMPTY;
        }else{
            account.cashBalance = account.cashBalance.add(rpnl);
            account.entrySocialLoss = account.entrySocialLoss.wmul(account.size.sub(amount).toInt256()).wdiv(
                account.size.toInt256()
            );
            account.entryFundingLoss = account.entryFundingLoss.wmul(account.size.sub(amount).toInt256()).wdiv(
                account.size.toInt256()
            );
            account.entryValue = account.entryValue.wmul(account.size.sub(amount)).wdiv(account.size);
            account.size = account.size.sub(amount);
            decreaseTotalSize(account.side, amount);        
        }
        return rpnl;
    }


    function trade(address trader, LibTypes.Side side, uint256 price, uint256 amount) internal returns (uint256,uint256) {
        // int256 rpnl;
        uint256 opened = amount;
        uint256 closed;
        LibTypes.MarginAccount memory account = marginAccounts[trader];
        LibTypes.Side originalSide = account.side;
        if (account.side != LibTypes.Side.FLAT&&account.side != LibTypes.Side.EMPTY&& account.side != side) {
            closed = account.size.min(amount);
            close(account, price, closed);
            opened = opened.sub(closed);
        }
        if (opened > 0) {
            open(account, side, price, opened);
        }
        marginAccounts[trader] = account;
        emit UpdatePositionAccount(trader, account, totalSize(originalSide), price);
        return (opened,closed);
    }

    /**
     * @dev Liqudate a bankrupt margin account (cash balance cannot cover negative pnl), force to sell its postion
     *      at mark price to the liquidator. The liquidated margin account will suffer a penalty.
     *      The liquidating process must be initiated from a margin account with enough margin balance.
     *      Any loss caused by liquidated account is firstly be recovered by insurance fund, then uncovered part
     *      will become socialloss and applied to the side of its couterparty.
     *
     * @param liquidator        Address who initiate the liquidating process.
     * @param trader            Address who is liquidated.
     * @param liquidationPrice  Price to liquidate.
     * @param liquidationAmount Max amount to liquidate.
     * @return Opened position amount for liquidate.
     */
    function liquidate(address liquidator, address trader, uint256 liquidationPrice, uint256 liquidationAmount)
        internal
        returns (uint256,uint256)
    {
        // liquidiated trader
        LibTypes.MarginAccount memory account = marginAccounts[trader];
        require(liquidationAmount <= account.size, "exceeded liquidation amount");

        LibTypes.Side liquidationSide = account.side;
        uint256 liquidationValue = liquidationPrice.wmul(liquidationAmount);
        int256 penaltyToLiquidator = governance.liquidationPenaltyRate.wmul(liquidationValue).toInt256();
        int256 penaltyToFund = governance.penaltyFundRate.wmul(liquidationValue).toInt256();

        // position: trader => liquidator
        trade(trader, LibTypes.counterSide(liquidationSide), liquidationPrice, liquidationAmount);
        (uint256 opened,uint256 closed) = trade(liquidator, liquidationSide, liquidationPrice, liquidationAmount);

        // penalty: trader => liquidator, trader => insuranceFundBalance
        updateCashBalance(trader, penaltyToLiquidator.add(penaltyToFund).neg());
        updateCashBalance(liquidator, penaltyToLiquidator);
        insuranceFundBalance = insuranceFundBalance.add(penaltyToFund);

        // loss
        int256 liquidationLoss = ensurePositiveBalance(trader).toInt256();
        // fund, fund penalty - possible social loss
        if (insuranceFundBalance >= liquidationLoss) {
            // insurance covers the loss
            insuranceFundBalance = insuranceFundBalance.sub(liquidationLoss);
        } else {
            // insurance cannot covers the loss, overflow part become socialloss of counter side.
            int256 newSocialLoss = liquidationLoss.sub(insuranceFundBalance);
            insuranceFundBalance = 0;
            handleSocialLoss(LibTypes.counterSide(liquidationSide), newSocialLoss);
        }
        require(insuranceFundBalance >= 0, "negtive insurance fund");

        emit UpdateInsuranceFund(insuranceFundBalance);
        return (opened,closed);
    }

    /**
     * @dev Increase social loss per contract on given side.
     *
     * @param side Side of position.
     * @param loss Amount of loss to handle.
     */
    function handleSocialLoss(LibTypes.Side side, int256 loss) internal {
        require(side != LibTypes.Side.FLAT, "side can't be flat");
        require(side != LibTypes.Side.EMPTY, "side can't be empty");
        require(totalSize(side) > 0, "size cannot be 0");
        require(loss >= 0, "loss must be positive");

        int256 newSocialLoss = loss.wdiv(totalSize(side).toInt256());
        int256 newLossPerContract = socialLossPerContracts[uint256(side)].add(newSocialLoss);
        socialLossPerContracts[uint256(side)] = newLossPerContract;

        emit SocialLoss(side, newLossPerContract);
    }

     /**
     * @dev Update the cash balance of a collateral account. Depends on the signed of given amount,
     *      it could be increasing (for positive amount) or decreasing (for negative amount).
     *
     * @param trader    Address of account owner.
     * @param wadAmount Amount of balance to be update. Both positive and negative are avaiable.
     */
    function updateCashBalance(address trader, int256 wadAmount) internal {
        if (wadAmount == 0) {
            return;
        }
        marginAccounts[trader].cashBalance = marginAccounts[trader].cashBalance.add(wadAmount);
        emit InternalUpdateBalance(trader, wadAmount, marginAccounts[trader].cashBalance);
    }

    /**
     * @dev Check a trader's cash balance, return the negative part and set the cash balance to 0
     *      if possible.
     *
     * @param trader    Address of account owner.
     * @return loss A loss equals to the negative part of trader's cash balance before operating.
     */
    function ensurePositiveBalance(address trader) internal returns (uint256 loss) {
        if (marginAccounts[trader].cashBalance < 0) {
            loss = marginAccounts[trader].cashBalance.neg().toUint256();
            marginAccounts[trader].cashBalance = 0;
        }
    }

    /**
     * @dev Like erc20's 'transferFrom', transfer internal balance from one account to another.
     *
     * @param from      Address of the cash balance transferred from.
     * @param to        Address of the cash balance transferred to.
     * @param wadAmount Amount of the balance to be transferred.
     */
    function transferBalance(address from, address to, int256 wadAmount) internal {
        if (wadAmount == 0) {
            return;
        }
        require(wadAmount > 0, "amount must be greater than 0");
        marginAccounts[from].cashBalance = marginAccounts[from].cashBalance.sub(wadAmount); // may be negative balance
        marginAccounts[to].cashBalance = marginAccounts[to].cashBalance.add(wadAmount);
        emit Transfer(from, to, wadAmount, marginAccounts[from].cashBalance, marginAccounts[to].cashBalance);
    }
}
