import dotenv from "dotenv";

// Parsing the env file.
dotenv.config();

interface ENV {
    WALLET: string;
}
// Loading process.env as ENV interface

const getConfig = (): ENV => {
  return {
    WALLET: process.env.WALLET,
  };
};

const cf = getConfig();

export default cf;