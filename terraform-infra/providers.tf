terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.37.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}

# azure cli ile login olunmalı
# az login
 