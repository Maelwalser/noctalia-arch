export VOLTA_HOME="$HOME/.volta"
export CARGO_HOME="$HOME/.cargo"
export PATH="$CARGO_HOME/bin:$VOLTA_HOME/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"
export GEMINI_API_KEY=$(pass show gemini/api_key)

export PATH="$HOME/development/flutter/bin:$PATH"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000

export GOPROXY=https://proxy.golang.org,direct

export PATH=$PATH:$(go env GOPATH)/bin
