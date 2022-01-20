// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

import {HardhatRuntimeEnvironment} from "hardhat/types";


async function deployment(hre: HardhatRuntimeEnvironment): Promise<void> {
  const {deployments, getNamedAccounts, network, ethers} = hre
  const {deploy, save, getArtifact, execute, read} = deployments
  const {deployer, dev} = await getNamedAccounts()


  //contractReader、globalConfig、exchange、testToken只需要部署一次
  // ContractReader
  let contractRreader = await deploy("ContractReader", {
    from: deployer,
    log: true
  })

  // GlobalConfig
  let globalConfig = await deploy("GlobalConfig", {
    from: deployer,
    log: true
  })

  // exchange
  let exchange = await deploy("Exchange", {
    from: deployer,
    log: true,
    args: [globalConfig.address,6]
  })

  // mock collateral token，6代表token的精度
  let testToken = await deploy("MyTestToken", {
    from: deployer,
    log: true,
    args: ["USDT", "USDT",6]
  })


  // 以下每添加一个交易对，就需要部署一次
  // mock price oracle
  // BTC / ETH	18	0x6eFd3CCf5c673bd5A7Ea91b414d0307a5bAb9cC1
  // BTC / USD	8	0x0c9973e7a27d00e656B9f153348dA46CaD70d03d
  // ETH / USD	8	0x5f0423B1a6935dc5596e7A24d98532b67A0AeFd8
  // LINK / ETH	18	0x1a658fa1a5747d73D0AD674AF12851F7d74c998e
  // LINK / USD	8	0x52C9Eb2Cc68555357221CAe1e5f2dD956bC194E5
  // USDT / USD	8	0xb1Ac85E779d05C2901812d812210F6dE144b2df0
  let chainlinkAdapter = await deploy("ChainlinkAdapter",{
    from: deployer,
    log: true,
    args:["0x5f0423B1a6935dc5596e7A24d98532b67A0AeFd8",3600 * 6,false]
  })


  // Perpetual
  let perpetual = await deploy("Perpetual", {
    from: deployer,
    log: true,
    args: [globalConfig.address, dev, testToken.address, 6]
  })

  // Proxy
  let proxy = await deploy("Proxy", {
    from: deployer,
    log: true,
    args: [perpetual.address]
  })

  // Funding
  let funding = await deploy("Funding", {
    from: deployer,
    log: true,
    args: [globalConfig.address, proxy.address, chainlinkAdapter.address]
  })

  // whitelist addComponent
  console.log('whitelist exchange -> perpetual');
  await execute("GlobalConfig", {
    from: deployer
  }, "addComponent", exchange.address, perpetual.address);

  console.log('whitelist perpetual -> exchange');
  await execute("GlobalConfig", {
    from: deployer
  }, "addComponent", perpetual.address, exchange.address);

  console.log('whitelist perpetual -> funding');
  await execute("GlobalConfig", {
    from: deployer
  }, "addComponent", perpetual.address, funding.address);

  console.log('whitelist funding -> perpetual');
  await execute("GlobalConfig", {
    from: deployer
  }, "addComponent", funding.address, perpetual.address);

  console.log('whitelist perpetual -> proxy');
  await execute("GlobalConfig", {
    from: deployer
  }, "addComponent", perpetual.address, proxy.address);

  console.log('whitelist funding -> exchange');
  await execute("GlobalConfig", {
    from: deployer
  }, "addComponent", funding.address, exchange.address);


  // set perpetual funding
  await execute("Perpetual", {
    from: deployer,
  }, "setGovernanceAddress", ethers.utils.formatBytes32String("fundingModule"), funding.address)
  console.log("set funding address done")

  //set perpetual gov
  await execute("Perpetual", {
    from: deployer,
  }, "setGovernanceParameter", ethers.utils.formatBytes32String("initialMarginRate"), ethers.BigNumber.from(10).pow(16).mul(4))
  console.log("set initialMarginRate done")

  await execute("Perpetual", {
    from: deployer,
  }, "setGovernanceParameter", ethers.utils.formatBytes32String("maintenanceMarginRate"), ethers.BigNumber.from(10).pow(16).mul(3))
  console.log("set maintenanceMarginRate done")

  await execute("Perpetual", {
    from: deployer,
  }, "setGovernanceParameter", ethers.utils.formatBytes32String("liquidationPenaltyRate"), ethers.BigNumber.from(10).pow(15).mul(18))
  console.log("set liquidationPenaltyRate done")

  await execute("Perpetual", {
    from: deployer,
  }, "setGovernanceParameter", ethers.utils.formatBytes32String("penaltyFundRate"), ethers.BigNumber.from(10).pow(15).mul(12))
  console.log("set penaltyFundRate done")

  await execute("Perpetual", {
    from: deployer,
  }, "setGovernanceParameter", ethers.utils.formatBytes32String("lotSize"), ethers.BigNumber.from(10).pow(15).mul(1))
  console.log("set lotSize done")

  await execute("Perpetual", {
    from: deployer,
  }, "setGovernanceParameter", ethers.utils.formatBytes32String("tradingLotSize"), ethers.BigNumber.from(10).pow(15).mul(1))
  console.log("set tradingLotSize done")

  await execute("Perpetual", {
    from: deployer,
  }, "setGovernanceParameter", ethers.utils.formatBytes32String("referrerBonusRate"), ethers.BigNumber.from(10).pow(17).mul(3))
  console.log("set referrerBonusRate done")

  //set funding gov
  await execute("Funding",{
    from: deployer,
  },"setGovernanceParameter",ethers.utils.formatBytes32String("emaAlpha"),3327787021630616)
  console.log("set emaAlpha done")

  await execute("Funding",{
    from: deployer,
  },"setGovernanceParameter",ethers.utils.formatBytes32String("markPremiumLimit"),ethers.BigNumber.from(10).pow(14).mul(8))
  console.log("set markPremiumLimit done")
  
  await execute("Funding",{
    from: deployer,
  },"setGovernanceParameter",ethers.utils.formatBytes32String("fundingDampener"),ethers.BigNumber.from(10).pow(14).mul(4))
  console.log("set fundingDampener done")
  
  // init funding
  await execute("Funding", {
    from: deployer
  }, "initFunding")
  console.log("initFunding done")
}

deployment.tags = ["ArbTest", "Arb"]
export default deployment
