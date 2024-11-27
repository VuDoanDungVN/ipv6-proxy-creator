#!/bin/sh

# Hàm tạo chuỗi ngẫu nhiên
random() {
  tr </dev/urandom -dc A-Za-z0-9 | head -c5
  echo
}

# Mảng các ký tự hexadecimal cho IPv6
array=(0 1 2 3 4 5 6 7 8 9 a b c d e f)

# Hàm tạo địa chỉ IPv6 ngẫu nhiên
gen64() {
  ip64() {
    echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
  }
  echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Cài đặt 3proxy
install_3proxy() {
  echo "Cài đặt 3proxy..."
  URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
  wget -qO- $URL | bsdtar -xvf-
  cd 3proxy-3proxy-0.8.6
  make -f Makefile.Linux
  mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
  cp src/3proxy /usr/local/etc/3proxy/bin/
  cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
  chmod +x /etc/init.d/3proxy
  chkconfig 3proxy on
  cd $WORKDIR
}

# Hàm tạo file cấu hình 3proxy
gen_3proxy() {
  cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

# Thêm người dùng từ tệp dữ liệu
users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

# Cấu hình proxy cho mỗi người dùng
$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

# Hàm tạo file proxy.txt cho người dùng
gen_proxy_file_for_user() {
  cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

# Hàm tải file proxy lên dịch vụ lưu trữ
upload_proxy() {
  local PASS=$(random)
  zip --password $PASS proxy.zip proxy.txt
  URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

  echo "Proxy đã sẵn sàng! Định dạng: IP:PORT:LOGIN:PASS"
  echo "Tải về từ: ${URL}"
  echo "Mật khẩu: ${PASS}"
}

# Cài đặt jq để xử lý JSON
install_jq() {
  wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
  chmod +x ./jq
  cp jq /usr/bin
}

# Tạo dữ liệu proxy cho người dùng
gen_data() {
  seq $FIRST_PORT $LAST_PORT | while read port; do
    echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
  done
}

# Tạo các lệnh iptables để mở cổng
gen_iptables() {
  cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

# Tạo lệnh ifconfig để cấu hình IPv6
gen_ifconfig() {
  cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

# Cài đặt các ứng dụng cần thiết
echo "Cài đặt các ứng dụng..."
yum -y install gcc net-tools bsdtar zip >/dev/null

# Cài đặt 3proxy
install_3proxy

# Thiết lập thư mục làm việc
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

# Lấy địa chỉ IP v4 và v6 của máy chủ
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Địa chỉ IP nội bộ = ${IP4}. Địa chỉ IPv6 = ${IP6}"

# Yêu cầu số lượng proxy cần tạo
echo "Bạn muốn tạo bao nhiêu proxy? Ví dụ: 500"
read COUNT

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))

# Tạo dữ liệu proxy
gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x boot_*.sh /etc/rc.local

# Tạo cấu hình 3proxy
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

# Cập nhật rc.local để cấu hình khi khởi động lại
cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
service 3proxy start
EOF

bash /etc/rc.local

# Tạo file proxy cho người dùng
gen_proxy_file_for_user

# Tải lên proxy
install_jq && upload_proxy
