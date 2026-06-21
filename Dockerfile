FROM rocker/shiny-verse:4.4.0


RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*


RUN install2.r --error --skipinstalled \
    bslib \
    plotly \
    DT \
    scales


COPY app.R /srv/shiny-server/app.R
COPY R/ /srv/shiny-server/R/
COPY data/ /srv/shiny-server/data/


EXPOSE 7860

CMD ["R", "-e", "shiny::runApp('/srv/shiny-server', host='0.0.0.0', port=7860)"]
