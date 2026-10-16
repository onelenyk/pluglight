Встановлення однією командою:

```sh
curl -fsSL https://raw.githubusercontent.com/onelenyk/magsafe-light/main/get.sh | sh
```

Або завантаж `MagSafe-Light.zip`, розпакуй і перенеси в «Програми». Програма не підписана сертифікатом Apple, тому перший запуск такий: відкрий програму, macOS її заблокує → Системні параметри → Конфіденційність і безпека → «Все одно відкрити». Або в терміналі: `xattr -dr com.apple.quarantine "/Applications/MagSafe Light.app"`.

Потрібен Mac з Apple Silicon і MagSafe 3, macOS 13 або новіша.
