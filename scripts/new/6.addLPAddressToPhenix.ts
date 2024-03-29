import { ethers } from "hardhat";
import ca from "./contractAddresses";

async function main() {
    const phenixTokenContract = await ethers.getContractAt("PhenixFinance", ca.phenixTokenAddress);

    console.log(`[ ------- Adding LP Address ${await phenixTokenContract.name()} (${await phenixTokenContract.symbol()}) ------- ]`);
    await phenixTokenContract.addLPAddress("0x49395041902BB59d9CdFF6DdF957E637fefaD432");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
