#!/bin/bash
set -e

# Hàm tạo chuỗi ngẫu nhiên
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# Mảng các ký tự hexadecimal cho IPv6
declare -a array=(0 1 2 3 4 5 6 7 8 9 a b c d e f)

# Hàm tạo địa chỉ IPv6 ngẫu nhiên
gen64() {
    local ip64() {
        printf "%s%s%s%s" "${array[$RANDOM % 16]}" "${array[$RANDOM % 16]}" "${array[$RANDOM % 16]}" "${array[$RANDOM % 16]}"
    }
    printf "%s:%s:%s:%s:%s\n" "$1" "$(ip64)" "$(ip64)" "$(ip64)" "$(ip64)"
}

# Cài đặt 3proxy
install_3proxy() {
    echo "installing 3proxy"
    local URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
    wget -qO- "$URL" | bsdtar -xvf- || { echo "Lỗi: Tải 3proxy thất bại"; exit 1; }
    cd 3proxy-3proxy-0.8.6 || { echo "Lỗi: Không thể chuyển vào thư mục 3proxy"; exit 1; }
    make -f Makefile.Linux || { echo "Lỗi: Biên dịch 3proxy thất bại"; exit 1; }
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat} || { echo "Lỗi: Không thể tạo thư mục 3proxy"; exit 1; }
    cp src/3proxy /usr/local/etc/3proxy/bin/ || { echo "Lỗi: Không thể copy file 3proxy"; exit 1; }
    cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy || { echo "Lỗi: Không thể copy file khởi động 3proxy"; exit 1; }
    chmod +x /etc/init.d/3proxy || { echo "Lỗi: Không thể cấp quyền cho file khởi động 3proxy"; exit 1; }
    systemctl enable 3proxy || { echo "Lỗi: Không thể bật dịch vụ 3proxy"; exit 1; }
    cd "$WORKDIR"
}


# Hàm tạo file cấu hình 3proxy
gen_3proxy() {
    local tmp_config=$(mktemp)
    printf "daemon\n" > "$tmp_config"
    printf "maxconn 1000\n" >> "$tmp_config"
    printf "nscache 65536\n" >> "$tmp_config"
    printf "timeouts 1 5 30 60 180 1800 15 60\n" >> "$tmp_config"
    printf "setgid 65535\n" >> "$tmp_config"
    printf "setuid 65535\n" >> "$tmp_config"
    printf "flush\n" >> "$tmp_config"
    printf "auth strong\n" >> "$tmp_config"

    # Thêm người dùng từ tệp dữ liệu
    printf "users $(awk -F/ 'BEGIN{ORS=\"\";} {print \$1 \":CL:\" \$2 \" \"}' \"${WORKDATA}\")\n" >> "$tmp_config"

    while IFS='/' read user pass ip4 port ip6; do
      printf "auth strong\n" >> "$tmp_config"
      printf "allow %s\n" "$user" >> "$tmp_config"
      printf "proxy -6 -n -a -p %s -i %s -e %s\n" "$port" "$ip4" "$ip6" >> "$tmp_config"
      printf "flush\n" >> "$tmp_config"
    done < "$WORKDATA"

    cp "$tmp_config" /usr/local/etc/3proxy/3proxy.cfg || { echo "Lỗi: Copy cấu hình 3proxy thất bại"; exit 1; }
}


# Hàm tạo file proxy.txt cho người dùng
gen_proxy_file_for_user() {
    cat > proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' "${WORKDATA}")
EOF
}


# Hàm tải file proxy lên dịch vụ lưu trữ
upload_proxy() {
    local PASS=$(random)
    zip --password "$PASS" proxy.zip proxy.txt || { echo "Lỗi: Nén file proxy thất bại"; exit 1; }
    local URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

    echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
    echo "Download zip archive from: ${URL}"
    echo "Password: ${PASS}"

}


# Tạo dữ liệu proxy cho người dùng
gen_data() {
    seq "$FIRST_PORT" "$LAST_PORT" | while read port; do
        printf "usr%s/pass%s/%s/%s/%s\n" "$(random)" "$(random)" "$IP4" "$port" "$(gen64 "$IP6")"
    done
}


# Tạo các lệnh iptables để mở cổng
gen_iptables() {
   local tmp_iptables=$(mktemp)
  while IFS='/' read user pass ip4 port ip6; do
    printf "firewall-cmd --permanent --add-port=%s/tcp\n" "$port" >> "$tmp_iptables"
  done < "$WORKDATA"
  cp "$tmp_iptables" "$WORKDIR/boot_iptables.sh" || { echo "Lỗi: Copy iptables config failed."; exit 1; }
  chmod +x "$WORKDIR/boot_iptables.sh" || { echo "Lỗi: Cấp quyền chạy cho boot_iptables.sh thất bại"; exit 1; }

  printf "firewall-cmd --reload\n" >> "$tmp_iptables"
  chmod +x "$tmp_iptables"
  bash "$tmp_iptables" || { echo "Lỗi: Chạy iptables thất bại"; exit 1; }
}


# Tạo lệnh cấu hình IPv6
gen_ifconfig() {
  local tmp_ifconfig=$(mktemp)
  while IFS='/' read user pass ip4 port ip6; do
    printf "ip -6 addr add %s/64 dev eth0\n" "$ip6" >> "$tmp_ifconfig"
  done < "$WORKDATA"
  cp "$tmp_ifconfig" "$WORKDIR/boot_ifconfig.sh" || { echo "Lỗi: Copy ifconfig config failed."; exit 1; }
  chmod +x "$WORKDIR/boot_ifconfig.sh" || { echo "Lỗi: Cấp quyền chạy cho boot_ifconfig.sh thất bại"; exit 1; }
  bash "$tmp_ifconfig" || { echo "Lỗi: Chạy ifconfig thất bại"; exit 1; }
}