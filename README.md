# SB-RESTAS-DAEMON

For English text see below

Запуск связки Hunchentoot + RESTAS на FreeBSD.
На основе restas-daemon.lisp, сделанного Archimag'ом для Linux,
подготовлен механизм демонизации RESTAS для FreeBSD.

Демонизация делается при помощи пакета SB-DAEMON Nikodemus Siivola.

# Как это запустить?

1. Необходимо, чтобы ваша система загружалась при помощи Quicklisp.
   (здесь и далее ваша система обозначается идентификатором "bates")


   (ql:quickload "bates")

   
2. Необходимо, чтобы Quicklisp мог загрузить систему [SB-DAEMON](https://github.com/nikodemus/sb-daemon).
   Этой системы нет в Quicklisp, поэтому ее нужно сделать доступной (копированием
   файлов или созданием ссылки на *.asd)
   
3. Файлы `restas-daemon.lisp` и `bates.conf` нужно скопировать в папку `/usr/local/etc/restas/`,
   а файл `bates` в `/usr/local/etc/rc.d/`.
   
4. Правите содержимое `bates.conf` по вкусу.

5. Теперь, запустив `/usr/local/etc/rc.d/bates onestart` должен произойти запуск вашего RESTAS-сервера.

6. PID-файл кладется при запуске в `/var/run/bates/bates.pid`, fasl - в `/var/cache/bates/fasl/`.

7. Добавляете `bates_enable="YES"` в `/etc/rc.conf` для возможности запускать демона при рестарте
   системы.
   
# How start the things?

1. Make sure your system can be started with Quicklisp:
   (your system refered as "bates")

   (ql:quickload "bates")
   
2. Make sure Quicklisp can find [SB-DAEMON](https://github.com/nikodemus/sb-daemon).

3. Copy files `restas-daemon.lisp` and `bates.conf` to `/usr/local/etc/restas/`,
   and `bates` to `/usr/local/etc/rc.d/`.
   
4. Edit `bates.conf` as you need.

5. Try `/usr/local/etc/rc.d/bates onestart`, your RESTAS-server has to start.

6. Look for PID file at `/var/run/bates/bates.pid`, *.fasl files at `/var/cache/bates/fasl/`.

7. Append `bates_enable="YES"` to `/etc/rc.conf` to be able to start your system during boot.
