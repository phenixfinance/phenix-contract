import { ethers } from "hardhat";
import ca from "./contractAddresses";

async function main() {
    const signers = await ethers.getSigners();
    const phenixTokenContract = await ethers.getContractAt("Phenix", ca.phenixTokenAddress);

    console.log(`[ ------- Break Selling ${await phenixTokenContract.name()} (${await phenixTokenContract.symbol()}) ------- ]`);
    // await phenixTokenContract.connect(signers[0]).setInitialDistributionFinished();
    // await phenixTokenContract.connect(signers[0]).updateRouter("0x2fFAa0794bf59cA14F268A7511cB6565D55ed40b");
    // await phenixTokenContract.connect(signers[0]).setSwapBackSettings(true, 0, 10000);

    console.log(await phenixTokenContract.router());
    console.log(await phenixTokenContract.checkSwapThreshold());

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
