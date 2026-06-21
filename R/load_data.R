# R/load_data.R
# Veri yükleme katmanı + gösterge meta verisi.
# Uygulamadaki tüm veri buradan gelir; gerçek TÜİK verisini taktığında
# yalnızca data/saglik_il.csv değişir, aşağıdaki fonksiyonlar aynı kalır.

library(dplyr)
library(readr)
library(tibble)

# --- Gösterge meta verisi -----------------------------------------------------
# yon = "yuksek_iyi"  -> değer ne kadar yüksekse o kadar iyi
# yon = "dusuk_iyi"   -> değer ne kadar düşükse o kadar iyi
# birim = haritada/eksende gösterilen birim
gosterge_meta <- tibble::tribble(
  ~gosterge_kodu,  ~yon,          ~birim,
  "hekim_1000",    "yuksek_iyi",  "hekim / 1000 kişi",
  "yatak_1000",    "yuksek_iyi",  "yatak / 1000 kişi",
  "yasam_erkek",   "yuksek_iyi",  "yıl",
  "yasam_kadin",   "yuksek_iyi",  "yıl"
)

# --- Sağlık verisini oku (uzun/tidy format) -----------------------------------
# Beklenen sütunlar: il, yil, gosterge_kodu, gosterge, deger
load_saglik_data <- function(path = "data/saglik_il.csv") {
  readr::read_csv(
    path,
    col_types = cols(
      il            = col_character(),
      yil           = col_integer(),
      gosterge_kodu = col_character(),
      gosterge      = col_character(),
      deger         = col_double()
    ),
    locale = locale(encoding = "UTF-8")
  )
}

# --- İl sınırları (sf gerektirmeyen düz koordinat tablosu) --------------------
# Sütunlar: il, grup (poligon parçası), sira, long, lat. ggplot geom_polygon için.
load_polygons <- function(path = "data/tr_polygons.csv") {
  readr::read_csv(
    path,
    col_types = cols(il = col_character(), grup = col_character(),
                     sira = col_integer(), long = col_double(), lat = col_double()),
    locale = locale(encoding = "UTF-8")
  )
}

# --- Seçili gösterge için yön bilgisini getir ---------------------------------
gosterge_yonu <- function(kod) {
  gosterge_meta$yon[gosterge_meta$gosterge_kodu == kod]
}

# --- Eşitsizlik özeti: en iyi / en kötü il + oran -----------------------------
# Tek bir gösterge-yıl dilimi için döner.
esitsizlik_ozeti <- function(df, kod) {
  yon <- gosterge_yonu(kod)
  if (yon == "yuksek_iyi") {
    en_iyi  <- df |> slice_max(deger, n = 1, with_ties = FALSE)
    en_kotu <- df |> slice_min(deger, n = 1, with_ties = FALSE)
  } else {
    en_iyi  <- df |> slice_min(deger, n = 1, with_ties = FALSE)
    en_kotu <- df |> slice_max(deger, n = 1, with_ties = FALSE)
  }
  list(
    en_iyi  = en_iyi,
    en_kotu = en_kotu,
    # en yüksek / en düşük oranı: 81 il arasındaki açıklığın tek sayılık ölçüsü
    oran    = max(df$deger, na.rm = TRUE) / min(df$deger, na.rm = TRUE)
  )
}
