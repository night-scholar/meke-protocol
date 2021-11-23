// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;
pragma abicoder v2;

import "../lib/LibTypes.sol";
import "../interface/IPerpetual.sol";


interface IFunding {
    function indexPrice() external view returns (uint256 price, uint256 timestamp);

    function lastFundingState() external view returns (LibTypes.FundingState memory);

    function currentFundingRate() external returns (int256);

    function currentFundingState() external returns (LibTypes.FundingState memory);

    function lastFundingRate() external view returns (int256);

    function getGovernance() external view returns (LibTypes.FundingGovernanceConfig memory);

    function perpetualProxy() external view returns (IPerpetual);

    function currentMarkPrice() external returns (uint256);

    function currentPremiumRate() external returns (int256);

    function currentFairPrice() external returns (uint256);

    function currentPremium() external returns (int256);

    function currentAccumulatedFundingPerContract() external returns (int256);

    function setFairPrice(uint256 price) external;
}
