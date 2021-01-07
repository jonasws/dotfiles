spacemacs: ## Update spacemacs distribution
	git -C ~/.emacs.d pull --rebase

intellimacs: ## Update intellimacs distribution
	git -C ~/.intellimacs pull --rebase

fish: ## Update fish things
	fisher

homebrew: ## Update brew formulae
	brew update && brew upgrade && brew upgrade --cask

default: homebrew spacemacs intellimacs fish

.DEFAULT_GOAL := default
