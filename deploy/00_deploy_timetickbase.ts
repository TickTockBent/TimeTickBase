import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deployTimeTickBase: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  // For testing, we can use the deployer as the dev fund address
  // You may want to change this for production
  const devFundAddress = deployer;

  await deploy('TimeTickBase', {
    from: deployer,
    args: [devFundAddress],
    log: true,
    autoMine: true,
  });
};

export default deployTimeTickBase;
deployTimeTickBase.tags = ['TimeTickBase'];
