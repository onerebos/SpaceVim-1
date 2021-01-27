#!/bin/bash

function backup() {
    if [[ -z "$1" ]] ;then
        echo -e "\033[31mError: backup() required one parameter\033[m"
        exit 1
    elif [[ -e "$1" ]] ;then
        mv "$1" "$1".bak
    fi
}

function makedir() {
    if [[ -z "$1" ]] ;then
        echo -e "\033[31mError: makedir() required one parameter\033[m"
        exit 1
    elif [[ ! -d "$1" ]] ;then
        if [[ -e "$1" ]] ;then
            mv "$1" "$1".bak
        fi
        mkdir -p "$1"
    fi
}

# 下载仓库配置
if [[ ! -e ~/.SpaceVim ]] ;then
    git clone --depth=1 https://github.com/mrbeardad/SpaceVim ~/.SpaceVim
else
    echo -e "\033[33m~/.SpaceVim\033[m directory is exists, skip 'git clone'"
fi

# 安装init.toml
backup ~/.SpaceVim.d/
ln -svf ~/.SpaceVim/mode ~/.SpaceVim.d

# 安装配置需要的命令
makedir ~/.local/bin
g++ -O3 -std=c++17 -o ~/.local/bin/quickrun_time ~/.SpaceVim/custom/quickrun_time.cpp

# 链接nvim配置
makedir ~/.config
backup ~/.config/nvim
ln -s ~/.SpaceVim ~/.config/nvim

# 安装合成的NerdCode字体
if [[ -z "$WSL_DISTRO_NAME" ]] ;then
    makedir ~/.local/share/fonts/NerdCode
    (
        cd ~/.local/share/fonts/NerdCode || exit 1
        curl -o ~/Downloads/NerdCode.tar.xz https://github.com/mrbeardad/DotFiles/raw/master/fonts/NerdCode.tar.xz || exit 1
        tar -Jxvf ~/Downloads/NerdCode.tar.xz
        echo -e "\032[32mInstalling NerdCode fonts ...\032[m"
        mkfontdir
        mkfontscale
        fc-cache -f
    )
fi

# 安装cppman数据缓存
makedir ~/.cache/cppman/cplusplus.com
(
    cd /tmp || exit 1
    curl -o ~/Downloads/cppman_db.tar.gz https://github.com/mrbeardad/DotFiles/raw/master/cppman/cppman_db.tar.gz || exit 1
    tar -zxf ~/Downloads/cppman_db.tar.gz
    cp -vn cppplusplus.com/* ~/.cache/cppman/cplusplus.com
)

echo -e "\033[32m [Note]:\033[m Now, startup your neovim and execute command \033[36m:SPInstall\033[m to install all plugins.
When all the plug-ins are installed, you need to do one things following :
\033[38;5;249m# install YCM
\033[33mcd ~/.cache/vimfiles/repos/github.com/ycm-core/YouCompleteMe/ && ./install.py --clangd-completer"