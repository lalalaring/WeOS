# WeOS 构建入口
SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help check prepare build all verify clean shell

help:
	@echo "WeOS 构建目标："
	@echo "  make check     环境自检（Debian 版本、依赖、磁盘、CPU 指令集）"
	@echo "  make prepare   生成配置树并抓取外部资产"
	@echo "  make build     构建 ISO"
	@echo "  make all       check + prepare + build + verify"
	@echo "  make verify    校验产物"
	@echo "  make clean     清理构建目录"

check:
	./build.sh check

prepare:
	./build.sh prepare

build:
	./build.sh build

all:
	./build.sh all

verify:
	./build.sh verify

clean:
	./build.sh clean

shell:
	./build.sh shell
