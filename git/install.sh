#!/usr/local/bin/zsh

if [[ ! -a $HOME/.gitattributes ]]; then
    ln -s $DOTFILES/git/.gitattributes $HOME/.gitattributes
fi
