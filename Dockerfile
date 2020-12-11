FROM perl:5.32

RUN apt-get update && apt-get install -y libarchive-dev redis-server

WORKDIR tmp

COPY Makefile.PL .

RUN cpanm --notest .
