FROM rocker/shiny-verse:4.4.0

# Sistem bağımlılıkları (plotly ve DT için)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# R paketleri (sf/leaflet/terra YOK — bilerek)
RUN install2.r --error --skipinstalled \
    bslib \
    plotly \
    DT \
    scales

# Uygulama dosyalarını kopyala
COPY app.R /srv/shiny-server/app.R
COPY R/ /srv/shiny-server/R/
COPY data/ /srv/shiny-server/data/

# HF Spaces port 7860 bekler
EXPOSE 7860

CMD ["R", "-e", "shiny::runApp('/srv/shiny-server', host='0.0.0.0', port=7860)"]
