# data-raw/prepare_data.R
# ----------------------------------------------------------------------------
# Ham TÜİK tablolarını uygulamanın okuduğu tek tidy dosyaya (data/saglik_il.csv)
# dönüştürür. Uygulama kodu bu dosyaya bağlı değildir.
#
# Ham kaynaklar (TÜİK Veri Portalı):
#   tuik-hekim-yatak-dogum-olum.xls  -> bin kişiye hekim; toplam hastane yatağı
#   tuik-dogusta-yasam-suresi.xls    -> doğuşta beklenen yaşam süresi (E/K)
#   tuik-il-nufus.xlsx               -> il nüfusu (yatağı bin kişiye normalize için)
#
# Çalıştırma:  source("data-raw/prepare_data.R")
# ----------------------------------------------------------------------------
library(readxl); library(dplyr); library(tidyr); library(stringr); library(readr); library(jsonlite)

TR_ILLERI <- fromJSON("geo/tr-iller.geojson")$features$properties$name
DUZELT    <- c("Afyonkarahisar" = "Afyon")   # pivot başlıklarındaki yazım farkı

# Türkçe il adını ortak ASCII anahtara indir (İ/ı büyük-harf farkını çözer) ----
anahtar <- function(x) {
  x <- str_remove_all(x, "\\(.*?\\)")
  x <- chartr("ıİIşŞğĞçÇöÖüÜâÂ", "iiisSgGcCoOuUaA", x)
  toupper(str_remove_all(x, "[^A-Za-z]"))
}
GEO_KEY <- setNames(TR_ILLERI, anahtar(TR_ILLERI))
GEO_KEY[anahtar("Afyonkarahisar")] <- "Afyon"

# TÜİK pivot bloğunu (il × yıl) uzun tabloya çeviren yardımcı ------------------
oku_blok <- function(path, satir_araligi, kod, etiket) {
  ham <- read_excel(path, col_names = FALSE)
  np  <- ncol(ham)
  iller <- ham[2, 4:np] |> unlist() |> as.character() |>
    str_remove("-\\d+$") |> str_trim() |> recode(!!!DUZELT)
  blok <- ham[satir_araligi, , drop = FALSE]
  vals <- blok[, 4:np]; colnames(vals) <- iller
  vals$yil <- suppressWarnings(as.integer(unlist(blok[, 3])))
  vals |>
    filter(!is.na(yil)) |>
    pivot_longer(-yil, names_to = "il", values_to = "deger") |>
    mutate(deger = suppressWarnings(as.numeric(deger))) |>
    filter(il %in% TR_ILLERI, !is.na(deger)) |>
    mutate(gosterge_kodu = kod, gosterge = etiket) |>
    select(il, yil, gosterge_kodu, gosterge, deger)
}

# İl nüfusu (uzun format: Yıl | İl | Toplam | Erkek | Kadın) -------------------
oku_nufus <- function(path) {
  read_excel(path, skip = 1) |>
    rename(yil = 1, il_ham = 2, nufus = 3) |>
    mutate(yil = suppressWarnings(as.integer(yil))) |>
    filter(!is.na(yil)) |>
    mutate(il = GEO_KEY[anahtar(il_ham)]) |>
    filter(!is.na(il)) |>
    select(il, yil, nufus)
}

hekim <- "data-raw/tuik-hekim-yatak-dogum-olum.xls"
yasam <- "data-raw/tuik-dogusta-yasam-suresi.xls"
nuf   <- "data-raw/tuik-il-nufus.xlsx"

# Bin kişiye yatak = toplam hastane yatağı / nüfus * 1000 ----------------------
yatak <- oku_blok(hekim, 85:100, "x", "x") |>          # 'Ölçüm bazında' = toplam yatak
  select(il, yil, yatak = deger) |>
  inner_join(oku_nufus(nuf), by = c("il", "yil")) |>
  transmute(il, yil, gosterge_kodu = "yatak_1000",
            gosterge = "Bin kişiye düşen hastane yatağı",
            deger = round(yatak / nufus * 1000, 2))

saglik <- bind_rows(
  oku_blok(hekim,  5:20, "hekim_1000",  "Bin kişiye düşen hekim"),                # 2009–2024
  yatak,                                                                          # 2009–2024
  oku_blok(yasam,  5:9,  "yasam_erkek", "Doğuşta beklenen yaşam süresi (Erkek)"), # 2013,14,17,20,23
  oku_blok(yasam, 10:14, "yasam_kadin", "Doğuşta beklenen yaşam süresi (Kadın)")
)

kontrol <- saglik |> group_by(gosterge_kodu) |> summarise(il = n_distinct(il))
stopifnot(all(kontrol$il == 81))

write_excel_csv(saglik, "data/saglik_il.csv")
message("Yazıldı: data/saglik_il.csv (", nrow(saglik), " satır, ",
        n_distinct(saglik$gosterge_kodu), " gösterge)")
