// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/PredictYieldMarketV2.sol";
import "../src/FlareSecureRandom.sol";

contract Deploy is Script {
    // Using deployer as placeholder for external contract addresses
    // In production, these would be actual Flare system contracts

    // Mock FXRP token for testing (we'll deploy our own)
    address public mockFXRP;

    // Deployment results
    FlareSecureRandom public secureRandom;
    PredictYieldMarketV2 public predictMarket;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log(
            "Deploying PredictYield contracts to Flare Coston2 testnet..."
        );
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Network: Coston2 (Chain ID: 114)");

        vm.startBroadcast(deployerPrivateKey);

        // 0. Deploy Mock FXRP token for testing
        console.log("\n=== Deploying Mock FXRP ===");
        mockFXRP = address(new MockFXRP());
        console.log("Mock FXRP deployed at:", mockFXRP);

        // 1. Deploy FlareSecureRandom with deployer as entropy source
        console.log("\n=== Deploying FlareSecureRandom ===");
        secureRandom = new FlareSecureRandom(deployer, deployer); // Using deployer as entropy source
        console.log("FlareSecureRandom deployed at:", address(secureRandom));

        // 2. Deploy PredictYieldMarketV2 (simplified version without oracle dependencies)
        console.log("\n=== Deploying PredictYieldMarketV2 ===");
        predictMarket = new PredictYieldMarketV2(
            mockFXRP,
            deployer, // Using deployer as oracle placeholder
            address(secureRandom),
            deployer
        );
        console.log(
            "PredictYieldMarketV2 deployed at:",
            address(predictMarket)
        );

        // 3. Create a demo market
        console.log("\n=== Creating Demo Market ===");
        uint256 marketId;
        try
            predictMarket.createMarket(
                "Will Aave USDC yield reach 5% by next week?",
                500, // 5% target yield
                2 days, // betting period
                true // use random duration
            )
        returns (uint256 id) {
            marketId = id;
            console.log("Demo market created with ID:", marketId);
        } catch {
            console.log("Failed to create demo market, continuing...");
            marketId = 0;
        }

        vm.stopBroadcast();

        // 4. Output deployment summary
        console.log("\n======= DEPLOYMENT SUMMARY =======");
        console.log("Network: Flare Coston2 Testnet");
        console.log("Chain ID: 114");
        console.log("RPC: https://coston2-api.flare.network/ext/C/rpc");
        console.log("Explorer: https://coston2-explorer.flare.network");
        console.log("");
        console.log("Mock FXRP:              ", mockFXRP);
        console.log("FlareSecureRandom:      ", address(secureRandom));
        console.log("PredictYieldMarketV2:   ", address(predictMarket));
        if (marketId > 0) {
            console.log("Demo Market ID:         ", marketId);
        }
        console.log("================================");

        // Save addresses to file for frontend integration
        string memory deploymentData = string(
            abi.encodePacked(
                "{\n",
                '  "networkId": 114,\n',
                '  "networkName": "Flare Coston2",\n',
                '  "rpcUrl": "https://coston2-api.flare.network/ext/C/rpc",\n',
                '  "explorerUrl": "https://coston2-explorer.flare.network",\n',
                '  "deployedAt": "',
                uintToString(block.timestamp),
                '",\n',
                '  "deployer": "',
                addressToString(deployer),
                '",\n',
                '  "contracts": {\n',
                '    "MockFXRP": "',
                addressToString(mockFXRP),
                '",\n',
                '    "FlareSecureRandom": "',
                addressToString(address(secureRandom)),
                '",\n',
                '    "PredictYieldMarketV2": "',
                addressToString(address(predictMarket)),
                '"\n',
                "  }"
            )
        );

        if (marketId > 0) {
            deploymentData = string(
                abi.encodePacked(
                    deploymentData,
                    ',\n  "demoMarketId": ',
                    uintToString(marketId),
                    "\n"
                )
            );
        } else {
            deploymentData = string(abi.encodePacked(deploymentData, "\n"));
        }

        deploymentData = string(abi.encodePacked(deploymentData, "}"));

        vm.writeFile("deployment-coston2.json", deploymentData);
        console.log("Deployment data saved to deployment-coston2.json");
        console.log("Ready for frontend integration!");
    }

    function addressToString(
        address _addr
    ) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    function uintToString(
        uint256 _i
    ) internal pure returns (string memory str) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        while (_i != 0) {
            k--;
            bstr[k] = bytes1(uint8(48 + (_i % 10)));
            _i /= 10;
        }
        str = string(bstr);
    }
}

// Simple Mock FXRP token for testing
contract MockFXRP {
    string public name = "Mock FXRP";
    string public symbol = "FXRP";
    uint8 public decimals = 18;
    uint256 public totalSupply = 1000000 * 10 ** 18; // 1M tokens

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(
            allowance[from][msg.sender] >= amount,
            "Insufficient allowance"
        );

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;

        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // Mint function for testing
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}
