---
author: robertwang
layout: post
title: rsync files to Android 
date:   2025-11-03
tags: 
  - rsync
  - sshd
  - obsidian
  - Android

---

我一直在使用 Obsidian，雖然不算是大量高頻率使用者，一兩年來還是累積了近千個檔案。

除了寫一些心得，我還會把 PDF 放在 Vault 裡，一邊讀一邊寫筆記或重點。當然我發現還是手寫對記憶最有幫助，儘管它可能散落在各個筆記本，畢竟我習慣不是很好，Bullet Journal 也荒廢了兩年，因為寫過後沒有很常回顧，沒有回顧就沒有它所謂的 migration，基本上 journaling 的效果就廢了一半，只剩下類似專注冥想反思的功能。

也接近年底了，也許重拾 Bullet Journal 可以排進明年的新希望之一。

好的進入本文主題。

累積大量的文件，免不了就是得同步到不同電腦上。Obsidian 本身提供[付費方案](https://help.obsidian.md/sync/switch)，身為免費仔的我，只把小小的 Vault 放在 iCloud 裡，任隨它進行同步。

我對同步這件事的看法是，這是廠商想要賣給你更多台裝置的陰謀（無論是手機平板筆電桌機）！當然這其中技術成分也不低，不能否認其中的價值，否則 DropBox 當初那麼紅而且還被幾家大公司邀請併購，直到 Apple, Google, Microsoft 都做出各自的同步版本。

你買越多台裝置，就檔案同步的問題就越大，讓你一個腦袋兩隻手在多裝置上忙不過來：廠商製造問題，接著廠商解決問題。

回到我自己的經驗來說，真正使用、真正需要生產力的電腦，並不會超過兩台，甚至說只有一台主要電腦，另一台只會是配角備用。以寫作的情境來說，不管是文章撰寫或是程式開發，舒服有生產力的環境通常需要合適的座位、鍵盤滑鼠，甚至是燈光，所以這通常只會有一套設備，一套專注沈浸在產出的設備，以及這套設備所搭配的環境，也就是說這是一套專用的輸出的配置（也可說我還不夠有錢）。

以 Obsidian 的使用情境來說，以檔案為主的同步機制早已普遍出現在各平台上。但我認為隨時頻繁同步的價值並不高，原因是產出裝置/環境只有一個，即使需要在其他裝置上閱讀，到時候再同步即可。

自從換掉 iPhone 回到 Android 後，我一直有同步 Obsidian Vault 到 Android 的需求，儘管頻率不高但一個禮拜或是一個月一次還是會發生的，偏手動的方式我想到了 rsync。

從 Mac 上把 Vault 搬到 Android 手機裡，這樣 Android 的 Obsidian App 也可以打開同一個 Vault。

### 需要的工具有：
- Android Phone
- Termux App
- rsync
- openssh


### 步驟：

1. 在 Termux 裡安裝這三項工具
> pkg install rysnc openssh termux-services
2. 執行 `termux-setup-storage` 給 termux 全域磁碟權限
3. 執行 `passwd` 設定密碼（讓 Mac 連線時輸入使用）
4. 執行 `sshd` 預設開在 port 8022 
5. 確認 Mac 及 Android 在同一個網域裡（192.168.X.X）
> 開啟手機熱點讓 Mac 連上就可以在同一個網域裡了
6. 確認 Android ip 位置在 `termux` 執行 `ipconfig`
> ipconfig 
> .....
> inet 192.168.11.88 
7. 在 `termux` 執行 `whoami` 並記下來稍後輸入
> u0_a345

### 將以下 script 存檔並改為可執行：

```shell
#!/bin/bash

# Rsync to Android (Termux) Script
# This script helps you sync files from Mac to Android via SSH/rsync

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Rsync to Android (Termux) ===${NC}\n"

# Check if rsync is installed
if ! command -v rsync &> /dev/null; then
    echo -e "${RED}Error: rsync is not installed${NC}"
    echo "Install it with: brew install rsync"
    exit 1
fi

# Get Android username
read -p "Enter Android username (e.g., u0_a123): " ANDROID_USER
if [ -z "$ANDROID_USER" ]; then
    echo -e "${RED}Username cannot be empty${NC}"
    exit 1
fi

# Get Android IP address
read -p "Enter Android IP address (e.g., 192.168.1.100): " ANDROID_IP
if [ -z "$ANDROID_IP" ]; then
    echo -e "${RED}IP address cannot be empty${NC}"
    exit 1
fi

# Get SSH port (default 8022)
read -p "Enter SSH port [default: 8022]: " SSH_PORT
SSH_PORT=${SSH_PORT:-8022}

# Get source directory
read -p "Enter source directory/file on Mac: " SOURCE_PATH
if [ -z "$SOURCE_PATH" ]; then
    echo -e "${RED}Source path cannot be empty${NC}"
    exit 1
fi

# Expand tilde in source path
SOURCE_PATH="${SOURCE_PATH/#\~/$HOME}"

# Check if source exists
if [ ! -e "$SOURCE_PATH" ]; then
    echo -e "${RED}Error: Source path does not exist: $SOURCE_PATH${NC}"
    exit 1
fi

# Get destination directory
echo -e "\n${YELLOW}Common Android destinations:${NC}"
echo "  ~/storage/downloads/  - Downloads folder"
echo "  ~/storage/shared/     - Internal storage"
echo "  ~/received/           - Home directory folder"
echo "  ~/                    - Termux home"
read -p "Enter destination path on Android: " DEST_PATH
if [ -z "$DEST_PATH" ]; then
    echo -e "${RED}Destination path cannot be empty${NC}"
    exit 1
fi

# Authentication method
echo -e "\n${YELLOW}Select authentication method:${NC}"
echo "  1) Password"
echo "  2) SSH key"
read -p "Enter choice [1-2]: " AUTH_METHOD

# Build rsync command
RSYNC_CMD="rsync -avzh --progress"

if [ "$AUTH_METHOD" = "2" ]; then
    read -p "Enter path to SSH private key [default: ~/.ssh/id_rsa]: " SSH_KEY
    SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
    SSH_KEY="${SSH_KEY/#\~/$HOME}"
    
    if [ ! -f "$SSH_KEY" ]; then
        echo -e "${RED}Error: SSH key not found: $SSH_KEY${NC}"
        exit 1
    fi
    
    RSYNC_CMD="$RSYNC_CMD -e \"ssh -p $SSH_PORT -i $SSH_KEY\""
else
    RSYNC_CMD="$RSYNC_CMD -e \"ssh -p $SSH_PORT\""
fi

# Add source and destination
RSYNC_CMD="$RSYNC_CMD \"$SOURCE_PATH\" ${ANDROID_USER}@${ANDROID_IP}:\"${DEST_PATH}\""

# Confirm before executing
echo -e "\n${YELLOW}=== Summary ===${NC}"
echo "Source:      $SOURCE_PATH"
echo "Destination: ${ANDROID_USER}@${ANDROID_IP}:${DEST_PATH}"
echo "SSH Port:    $SSH_PORT"
echo "Auth:        $([ "$AUTH_METHOD" = "2" ] && echo "SSH Key ($SSH_KEY)" || echo "Password")"
echo -e "\n${YELLOW}Command to execute:${NC}"
echo "$RSYNC_CMD"
echo

read -p "Proceed with transfer? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Transfer cancelled."
    exit 0
fi

# Test SSH connection first
echo -e "\n${YELLOW}Testing SSH connection...${NC}"
if [ "$AUTH_METHOD" = "2" ]; then
    ssh -p "$SSH_PORT" -i "$SSH_KEY" -o ConnectTimeout=5 "${ANDROID_USER}@${ANDROID_IP}" "echo 'Connection successful'" 2>/dev/null
else
    ssh -p "$SSH_PORT" -o ConnectTimeout=5 "${ANDROID_USER}@${ANDROID_IP}" "echo 'Connection successful'" 2>/dev/null
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ SSH connection successful${NC}\n"
else
    echo -e "${RED}✗ SSH connection failed. Please check:${NC}"
    echo "  - Android device is on the same network"
    echo "  - SSH server is running on Android (sshd)"
    echo "  - IP address and username are correct"
    echo "  - Port $SSH_PORT is accessible"
    exit 1
fi

# Execute rsync
echo -e "${YELLOW}Starting transfer...${NC}\n"
eval $RSYNC_CMD

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✓ Transfer completed successfully!${NC}"
else
    echo -e "\n${RED}✗ Transfer failed${NC}"
    exit 1
fi

# Ask if user wants to save configuration
echo -e "\n${YELLOW}Save this configuration for future use?${NC}"
read -p "(y/n): " SAVE_CONFIG
if [ "$SAVE_CONFIG" = "y" ] || [ "$SAVE_CONFIG" = "Y" ]; then
    CONFIG_FILE="$HOME/.rsync_android_config"
    echo "ANDROID_USER=\"$ANDROID_USER\"" > "$CONFIG_FILE"
    echo "ANDROID_IP=\"$ANDROID_IP\"" >> "$CONFIG_FILE"
    echo "SSH_PORT=\"$SSH_PORT\"" >> "$CONFIG_FILE"
    echo "AUTH_METHOD=\"$AUTH_METHOD\"" >> "$CONFIG_FILE"
    if [ "$AUTH_METHOD" = "2" ]; then
        echo "SSH_KEY=\"$SSH_KEY\"" >> "$CONFIG_FILE"
    fi
    echo -e "${GREEN}✓ Configuration saved to $CONFIG_FILE${NC}"
    echo "You can edit this file to quickly load settings next time"
fi
```

1. 存檔成 rsync_to_android.sh
2. chmod +x ./rsync_to_android.sh
3. ./rsync_to_android.sh

```
=== Rsync to Android (Termux) ===

Enter Android username (e.g., u0_a123): u0_a345
Enter Android IP address (e.g., 192.168.1.100): 192.168.11.88 
Enter SSH port [default: 8022]:
Enter source directory/file on Mac: /Users/robert.wang/Documents/ob_vault

Common Android destinations:
  ~/storage/downloads/  - Downloads folder
  ~/storage/shared/     - Internal storage
  ~/received/           - Home directory folder
  ~/                    - Termux home
Enter destination path on Android: /storage/emulated/0/Documents/

Select authentication method:
  1) Password
  2) SSH key
Enter choice [1-2]: 1

=== Summary ===
Source:      /Users/robert.wang/Documents/ob_vault
Destination: u0_a345@172.16.99.163:/storage/emulated/0/Documents/
SSH Port:    8022
Auth:        Password

Command to execute:
rsync -avzh --progress -e "ssh -p 8022" "/Users/robert.wang/Documents/ob_vault" u0_a345@172.16.99.163:"/storage/emulated/0/Documents/"

Proceed with transfer? (y/n): y

Testing SSH connection...
u0_a345@172.16.99.163's password:
Connection successful
✓ SSH connection successful

Starting transfer...

u0_a345@172.16.99.163's password:
Transfer starting: 6 files
WFH_LOG/
WFH_LOG/20250722_WFH.txt
             87 100%  240.78KB/s   00:00:00 (xfer#1, to-check=1/6)
WFH_LOG/20250826_WFH.txt
             23 100%   16.32KB/s   00:00:00 (xfer#2, to-check=2/6)
WFH_LOG/20250926_WFH.txt
             23 100%   30.19KB/s   00:00:00 (xfer#3, to-check=3/6)
WFH_LOG/20251031_WFH.txt
             16 100%   11.74KB/s   00:00:00 (xfer#4, to-check=4/6)

sent 123k bytes  received 136 bytes  369k bytes/sec
total size is 132k  speedup is 1.07

✓ Transfer completed successfully!

Save this configuration for future use?
(y/n): y
✓ Configuration saved to /Users/robert.wang/.rsync_android_config
You can edit this file to quickly load settings next time

```

[以上的 script 是由 Claude AI 產生](https://claude.ai/public/artifacts/e68c2a15-4b32-4003-b3bc-12e52be5b7c5)，實測過可以正常使用，並儲存前一次的設定方便下次使用

這樣就達到我久久一次的 Obsidian Vault 同步程序了！一點點研究，一點點麻煩，不過有 script 可以省掉很多心思了！

最後你還可以在 Mac 設定 alias，以便快速叫出這個指令：

> vim ~/.zshrc
> alias rsync-android='~/rsync-to-android.sh'