import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deployWrapper: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  // Get the TTB contract address from previous deployment
  const TTB = await deployments.get('TimeTickBase');

  // Example wrapper parameters
  const NAME = "Wrapped TTB";
  const SYMBOL = "wTTB";
  const WRAP_RATIO = 1000; // 1 TTB = 1000 wTTB
  const ALLOW_UNWRAP = true;

  await deploy('TTBWrapper', {
    from: deployer,
    args: [TTB.address, NAME, SYMBOL, WRAP_RATIO, ALLOW_UNWRAP],
    log: true,
    waitConfirmations: 1,
  });
};

deployWrapper.tags = ['TTBWrapper'];
deployWrapper.dependencies = ['TimeTickBase'];

export default deployWrapper;