#!/bin/bash

ATOM_DIR=$HOME/.atom

# Create ~/.atom if it doesn't exist
if [[ ! -d "$ATOM_DIR" ]]; then
  mkdir $ATOM_DIR
fi

for file in $DOTFILES/editor/atom/*
do
  if [[ "${file: -10}" != "install.sh" ]]; then
    ln -s $file $ATOM_DIR/$(basename $file)
  fi
done

apm install $(cat $DOTFILES/editor/atom/packages.list)
