FROM perl:5 AS perl

RUN apt update && \
    apt -y install liblog-any-perl libwww-perl libdbi-perl libparallel-forkmanager-perl libdbd-sqlite3-perl && \
    apt clean

WORKDIR /app
COPY app/ .
CMD ["/usr/bin/perl","/app/chk.pl"]
