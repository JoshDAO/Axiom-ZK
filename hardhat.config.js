require("@nomicfoundation/hardhat-toolbox")

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
	solidity: "0.8.20",
	networks: {
		hardhat: {
			chainId: 31337,
			forking: {
				url: "https://eth-goerli.g.alchemy.com/v2/DDQFORCbIn88uKaaVK0LJVOyFE51hhO3"
			}
		},
	}
}
