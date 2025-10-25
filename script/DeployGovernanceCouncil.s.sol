// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/console2.sol";
import {GovernanceCouncil} from "src/governance/GovernanceCouncil.sol";

/**
 * Deploy GovernanceCouncil using parameters from a JSON config file.
 *
 * Usage:
 * forge script script/DeployGovernanceCouncil.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify -vv
 *
 * Environment variables required:
 * - RPC_URL: RPC URL of the target network
 * - PRIVATE_KEY: Private key of the deployer (numeric, hex "0x..." also accepted by envUint)
 * - ETHERSCAN_API_KEY: API key for contract verification on Etherscan-compatible explorers
 * - COUNCIL_CONFIG: Path to JSON file with constructor parameters
 *
 * Config JSON shape (example in script/config/governance.council.example.json):
 * {
 *   "voters": ["0x...", "0x..."],
 *   "powers": [1, 1],
 *   "forwarders": ["0x..."],
 *   "activePeriod": 86400,
 *   "quorumThreshold": 60
 * }
 */
contract DeployGovernanceCouncil is Script {
    using stdJson for string;

    function run() external returns (GovernanceCouncil council) {
        // Read deployer key and config path
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        string memory configPath = vm.envString("COUNCIL_CONFIG");

        // Load and parse JSON config
        string memory json = vm.readFile(configPath);

        address[] memory voters = json.readAddressArray(".voters");
        uint256[] memory powers = json.readUintArray(".powers");
        address[] memory forwarders = json.readAddressArray(".forwarders");
        uint256 activePeriod = json.readUint(".activePeriod");
        uint256 quorumThreshold = json.readUint(".quorumThreshold");

        require(voters.length > 0, "Deploy: no voters");
        require(voters.length == powers.length, "Deploy: voters/powers length mismatch");

        vm.startBroadcast(deployerKey);
        council = new GovernanceCouncil(voters, powers, forwarders, activePeriod, quorumThreshold);
        vm.stopBroadcast();

        console2.log("GovernanceCouncil deployed at:", address(council));
    }
}
