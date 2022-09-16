import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-abi-exporter";
import cf from "./config";

const config: HardhatUserConfig = {
  solidity: "0.7.4",
  networks: {
    hardhat: {
    },
    cronostestnet: {
      url: "https://cronos-testnet-3.crypto.org:8545",
      accounts: [cf.WALLET]
    }
  },
};

export default config;
