import { ethers } from "hardhat";
import ca from "./contractAddresses";


async function main() {
  const phenixTokenContract = await ethers.getContractAt("PhenixFinance", ca.phenixTokenAddress);
  const router = await ethers.getContractAt("IVVSRouter", '0x2fFAa0794bf59cA14F268A7511cB6565D55ed40b');

  console.log(await router.WETH());

  var amountToSell = await phenixTokenContract.balanceOf("0x55DC352C9247ea5168687A26E219933f8bA7A493");
  console.log(ethers.utils.formatEther(amountToSell.toString()));

  console.log(Math.floor(Date.now() / 1000) + 20);
  await router
    .swapExactTokensForETHSupportingFeeOnTransferTokens(
        ethers.utils.parseEther("1000000"), 
        0, 
        ["0x01Dc08CD1924065330ff986Eb536b1b9b7ed0D42", "0xa85d35eb8E439078a1810Ec3738997E61d157f0d"],
        "0x55DC352C9247ea5168687A26E219933f8bA7A493",
        Math.floor(Date.now() / 1000) + 20
    );

    var amountToSell = await phenixTokenContract.balanceOf("0x55DC352C9247ea5168687A26E219933f8bA7A493");
  console.log(ethers.utils.formatEther(amountToSell.toString()));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
