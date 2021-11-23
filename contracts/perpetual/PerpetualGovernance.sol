// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;
pragma abicoder v2;

import "../lib/LibMath.sol";
import "../lib/LibTypes.sol";
import "./PerpetualStorage.sol";
import "../interface/IGlobalConfig.sol";

contract PerpetualGovernance is PerpetualStorage {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;

    event UpdateGovernanceParameter(bytes32 indexed key, int256 value);
    event UpdateGovernanceAddress(bytes32 indexed key, address value);

    constructor(address _globalConfig) {
        require(_globalConfig != address(0), "invalid global config");
        globalConfig = IGlobalConfig(_globalConfig);
    }

    // Check if sender is owner.
    modifier onlyOwner() {
        require(globalConfig.owner() == msg.sender, "not owner");
        _;
    }

    // Check if sender is authorized to call some critical functions.
    modifier onlyAuthorized() {
        require(globalConfig.isComponent(msg.sender), "unauthorized caller");
        _;
    }

    // Check if system is current paused. 
    modifier onlyNotPaused () {
        require(!paused, "system paused");
        _;
    }

    /**
     * @dev Set governance parameters.
     *
     * @param key   Name of parameter.
     * @param value Value of parameter.
     */
    function setGovernanceParameter(bytes32 key, int256 value) public onlyOwner {
        if (key == "initialMarginRate") {
            governance.initialMarginRate = value.toUint256();
            require(governance.initialMarginRate > 0, "require im > 0");
            require(governance.initialMarginRate < 10**18, "require im < 1");
            require(governance.maintenanceMarginRate < governance.initialMarginRate, "require mm < im");
        } else if (key == "maintenanceMarginRate") {
            governance.maintenanceMarginRate = value.toUint256();
            require(governance.maintenanceMarginRate > 0, "require mm > 0");
            require(governance.maintenanceMarginRate < governance.initialMarginRate, "require mm < im");
            require(governance.liquidationPenaltyRate < governance.maintenanceMarginRate, "require lpr < mm");
            require(governance.penaltyFundRate < governance.maintenanceMarginRate, "require pfr < mm");
        } else if (key == "liquidationPenaltyRate") {
            governance.liquidationPenaltyRate = value.toUint256();
            require(governance.liquidationPenaltyRate < governance.maintenanceMarginRate, "require lpr < mm");
        } else if (key == "penaltyFundRate") {
            governance.penaltyFundRate = value.toUint256();
            require(governance.penaltyFundRate < governance.maintenanceMarginRate, "require pfr < mm");
        } else if (key == "takerDevFeeRate") {
            governance.takerDevFeeRate = value;
        } else if (key == "makerDevFeeRate") {
            governance.makerDevFeeRate = value;
        } else if (key == "lotSize") {
            require(
                governance.tradingLotSize == 0 || governance.tradingLotSize.mod(value.toUint256()) == 0,
                "require tls % ls == 0"
            );
            governance.lotSize = value.toUint256();
        } else if (key == "tradingLotSize") {
            require(governance.lotSize == 0 || value.toUint256().mod(governance.lotSize) == 0, "require tls % ls == 0");
            governance.tradingLotSize = value.toUint256();
        } else if (key == "longSocialLossPerContracts") {
            require(status == LibTypes.Status.EMERGENCY, "wrong perpetual status");
            socialLossPerContracts[uint256(LibTypes.Side.LONG)] = value;
        } else if (key == "shortSocialLossPerContracts") {
            require(status == LibTypes.Status.EMERGENCY, "wrong perpetual status");
            socialLossPerContracts[uint256(LibTypes.Side.SHORT)] = value;
        } else if (key == "referrerBonusRate") {
            governance.referrerBonusRate = value;
            require(governance.referrerBonusRate > 0 && governance.referrerBonusRate <= 10 ** 18, "referrerBonusRate > 0 && referrerBonusRate <= 1");
        } else {
            revert("key not exists");
        }
        emit UpdateGovernanceParameter(key, value);
    }

    /**
     * @dev Set governance address. like set governance parameter.
     *
     * @param key   Name of parameter.
     * @param value Address to set.
     */
    function setGovernanceAddress(bytes32 key, address value) public onlyOwner {
        require(value != address(0), "invalid address");
        if (key == "dev") {
            devAddress = value;
        } else if (key == "fundingModule") {
            fundingModule = IFunding(value);
        } else if (key == "globalConfig") {
            globalConfig = IGlobalConfig(value);
        } else {
            revert("key not exists");
        }
        emit UpdateGovernanceAddress(key, value);
    }

    /** 
     * @dev Check amount with lot size. Amount must be integral multiple of lot size.
     */
    function isValidLotSize(uint256 amount) public view returns (bool) {
        return amount > 0 && amount.mod(governance.lotSize) == 0;
    }

    /**
     * @dev Check amount with trading lot size. Amount must be integral multiple of trading lot size.
     *      This is useful in trading to control minimal trading position size.
     */
    function isValidTradingLotSize(uint256 amount) public view returns (bool) {
        return amount > 0 && amount.mod(governance.tradingLotSize) == 0;
    }
}
