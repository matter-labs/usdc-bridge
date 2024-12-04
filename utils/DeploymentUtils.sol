// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

abstract contract DeploymentUtils is Script {
    using stdJson for string;

    function _getAddressesDir(uint256 chainId) internal view virtual returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/", vm.toString(chainId));
    }

    function _getAddressesFile(uint256 chainId) internal view virtual returns (string memory) {
        return string.concat(_getAddressesDir(chainId), "/addresses.json");
    }

    function getDeployedContract(string memory contractName, uint256 chainId) internal virtual returns (address) {
        try vm.readFile(_getAddressesFile(chainId)) returns (string memory json) {
            try vm.parseJsonAddress(json, string.concat(".", contractName)) returns (address addr) {
                return addr;
            } catch {
                return address(0);
            }
        } catch {
            return address(0);
        }
    }

    function getDeployedContract(string memory contractName) internal virtual returns (address) {
        return getDeployedContract(contractName, block.chainid);
    }

    function saveDeployedContract(string memory contractName, address addr) internal {
        string memory path = _getAddressesFile(block.chainid);
        string memory dir = _getAddressesDir(block.chainid);
        if (!vm.isDir(dir)) vm.createDir(dir, true);
        if (!vm.isFile(path)) {
            vm.writeFile(path, "{}");
        }

        string memory json = vm.readFile(path);
        string[] memory keys = vm.parseJsonKeys(json, "$");
        for (uint256 index = 0; index < keys.length; index++) {
            vm.serializeString(contractName, keys[index], json.readString(string.concat(".", keys[index])));
        }
        vm.writeJson(vm.serializeAddress(contractName, contractName, addr), path);
    }
}
