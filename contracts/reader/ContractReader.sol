// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;
pragma abicoder v2;

import "../lib/LibTypes.sol";
import "../interface/IPerpetual.sol";
import "../interface/IFunding.sol";

contract ContractReader {
    struct GovParams {
        LibTypes.PerpGovernanceConfig perpGovernanceConfig;
        LibTypes.FundingGovernanceConfig fundingModuleGovernanceConfig;
        address fundingModuleAddress; // funding module contract address
    }

    struct PerpetualStorage {
        address collateralTokenAddress;
        uint256 totalSize;
        int256 insuranceFundBalance;
        int256 longSocialLossPerContract;
        int256 shortSocialLossPerContract;
        bool isEmergency;
        bool isGlobalSettled;
        uint256 globalSettlePrice;
        bool isPaused;
        bool isWithdrawDisabled;
        LibTypes.FundingState fundingParams;
        uint256 oraclePrice;
        uint256 oracleTime;
    }

    struct TraderPosition {
        int256 marginBalance;
        uint256 markPrice;
        uint256 maintenanceMargin;
        PerpetualStorage perpetualStorage;
        LibTypes.MarginAccount marginAccount;
        int256 availableMargin;
    }


    struct LiquidateTrader {
        address trader;
        LibTypes.MarginAccount marginAccount;
    }

    struct Market {
        uint256 oraclePrice;
        uint256 oracleTime;
        uint256 totalSize;
        uint256 markPrice;
    }

    function getGovParams(address perpetualAddress) public view returns (GovParams memory params) {
        IPerpetual perpetual = IPerpetual(perpetualAddress);
        params.perpGovernanceConfig = perpetual.getGovernance();
        params.fundingModuleGovernanceConfig = perpetual.fundingModule().getGovernance();
        params.fundingModuleAddress = address(perpetual.fundingModule());
    }

    function getPerpetualStorage(address perpetualAddress) public view returns (PerpetualStorage memory params) {
        IPerpetual perpetual = IPerpetual(perpetualAddress);
        params.collateralTokenAddress = address(perpetual.collateral());

        params.totalSize = perpetual.totalSize(LibTypes.Side.LONG);
        params.insuranceFundBalance = perpetual.insuranceFundBalance();
        params.longSocialLossPerContract = perpetual.socialLossPerContract(LibTypes.Side.LONG);
        params.shortSocialLossPerContract = perpetual.socialLossPerContract(LibTypes.Side.SHORT);

        params.isEmergency = perpetual.status() == LibTypes.Status.EMERGENCY;
        params.isGlobalSettled = perpetual.status() == LibTypes.Status.SETTLED;
        params.globalSettlePrice = perpetual.settlementPrice();
        params.isPaused = perpetual.paused();
        params.isWithdrawDisabled = perpetual.withdrawDisabled();

        params.fundingParams = perpetual.fundingModule().lastFundingState();
        (params.oraclePrice, params.oracleTime) = perpetual.fundingModule().indexPrice();
    }

    function getAccountStorage(address perpetualAddress, address trader)
        public
        view
        returns (LibTypes.MarginAccount memory margin)
    {
        IPerpetual perpetual = IPerpetual(perpetualAddress);
        return perpetual.getMarginAccount(trader);
    }
    
    function TraderNeedLiquidate(address perpetualAddress,uint256 start,uint256 end) external returns(uint256 indexPrice,LiquidateTrader[10] memory params) {
        IPerpetual perpetual = IPerpetual(perpetualAddress);
        uint256 nums = 0;
        for (uint256 i = start; i < end; i++) {
            address trader = perpetual.accountList(i);
            if (!perpetual.isSafe(trader)) {
                params[nums].trader = trader;
                params[nums].marginAccount = perpetual.getMarginAccount(trader);
                nums = nums + 1;
            }
        }
        indexPrice = perpetual.markPrice();
    }

    function getTraderAllPosition(address[] memory perpetualAddresses, address trader) external returns(TraderPosition[10] memory params) {
        for (uint256 i = 0; i<perpetualAddresses.length; i++) {
            params[i] = getTraderPosition(perpetualAddresses[i],trader);
        }
    }

    function getAllMarket(address[] memory perpetualAddresses) external view returns(Market[10] memory params) {
        for (uint256 i = 0; i < perpetualAddresses.length; i++) {
            IPerpetual perpetual = IPerpetual(perpetualAddresses[i]);
            (params[i].oraclePrice, params[i].oracleTime) = perpetual.fundingModule().indexPrice();
            params[i].totalSize = perpetual.totalSize(LibTypes.Side.LONG);
        }
    }

    function getMarket(address[] memory perpetualAddresses) external returns(Market memory param) {
        for (uint256 i = 0; i < perpetualAddresses.length; i++) {
            IPerpetual perpetual = IPerpetual(perpetualAddresses[i]);
            (param.oraclePrice, param.oracleTime) = perpetual.fundingModule().indexPrice();
            param.totalSize = perpetual.totalSize(LibTypes.Side.LONG);
            param.markPrice = perpetual.markPrice();
        }
    }

    function getTraderPosition(address perpetualAddress,address trader) public returns (TraderPosition memory params) {
        IPerpetual perpetual = IPerpetual(perpetualAddress);
        params.marginBalance = perpetual.marginBalance(trader);
        params.markPrice = perpetual.markPrice();
        params.maintenanceMargin = perpetual.maintenanceMargin(trader);
        params.perpetualStorage = getPerpetualStorage(perpetualAddress);
        params.marginAccount = perpetual.getMarginAccount(trader);
        params.availableMargin = perpetual.availableMargin(trader);
    }
}