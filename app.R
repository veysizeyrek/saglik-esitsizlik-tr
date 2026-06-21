# app.R
# Türkiye'de Sağlıkta Bölgesel Eşitsizlik — interaktif Shiny paneli
# Çalıştırmak için: shiny::runApp()  (bağımlılıklar için README'ye bakın)

library(shiny)
library(bslib)
library(dplyr)
library(tidyr)
library(ggplot2)
library(plotly)
library(scales)
library(DT)

source("R/load_data.R", encoding = "UTF-8")

# --- Veriyi bir kez yükle (uygulama açılışında) -------------------------------
veri    <- load_saglik_data("data/saglik_il.csv")
poligon <- load_polygons("data/tr_polygons.csv")

# selectInput için "etiket = kod" eşlemesi (kullanıcı etiketi görür, kod döner)
gosterge_df      <- veri |> distinct(gosterge_kodu, gosterge) |> arrange(gosterge)
gosterge_secenek <- setNames(gosterge_df$gosterge_kodu, gosterge_df$gosterge)

# Her göstergenin TÜİK'te mevcut yılları farklı (ör. yaşam süresi yalnızca
# 2013,2014,2017,2020,2023). Yıl seçeneği bu yüzden göstergeye göre güncellenir.
yillar_of <- function(kod) sort(unique(veri$yil[veri$gosterge_kodu == kod]), decreasing = TRUE)

varsayilan_gosterge <- if ("hekim_1000" %in% gosterge_secenek) "hekim_1000" else gosterge_secenek[[1]]
ilk_yillar <- yillar_of(varsayilan_gosterge)
il_listesi <- sort(unique(veri$il))

# Kırmızı = kötü olacak şekilde tema rengi
KOTU_KIRMIZI <- "#c0392b"; IYI_YESIL <- "#27ae60"; ANA_RENK <- "#1f6f8b"

# ============================= ARAYÜZ =========================================
ui <- page_sidebar(
  title = "Türkiye'de Sağlıkta Bölgesel Eşitsizlik",
  theme = bs_theme(version = 5, bootswatch = "flatly", primary = ANA_RENK),

  sidebar = sidebar(
    width = 300,
    selectInput("gosterge", "Gösterge", choices = gosterge_secenek,
                selected = varsayilan_gosterge),
    selectInput("yil", "Yıl", choices = ilk_yillar, selected = max(ilk_yillar)),
    hr(),
    div(
      class = "small text-muted",
      strong("Kaynak: TÜİK."),
      " Bin kişiye hekim 2009–2024; doğuşta beklenen yaşam süresi yalnızca ",
      "2013, 2014, 2017, 2020, 2023 dönemleri için yayımlanır. ",
      "Yıl listesi seçtiğin göstergeye göre değişir."
    )
  ),

  # Üst KPI kutuları
  layout_columns(
    fill = FALSE,
    value_box(
      title = "En iyi / en kötü il oranı",
      value = textOutput("kpi_oran"),
      showcase = NULL, theme = "primary",
      p(class = "small", "81 il arasındaki açıklık")
    ),
    value_box(
      title = "En iyi il",
      value = textOutput("kpi_iyi"),
      theme = value_box_theme(bg = IYI_YESIL, fg = "white")
    ),
    value_box(
      title = "En kötü il",
      value = textOutput("kpi_kotu"),
      theme = value_box_theme(bg = KOTU_KIRMIZI, fg = "white")
    )
  ),

  navset_card_tab(
    nav_panel(
      "Harita",
      card_body(
        p(class = "text-muted small", textOutput("harita_aciklama", inline = TRUE)),
        plotlyOutput("harita", height = 520)
      )
    ),
    nav_panel(
      "Sıralama",
      card_body(
        p(class = "text-muted small",
          "En iyi ve en kötü 10 il. Kırmızı = kötü, yeşil = iyi."),
        plotOutput("siralama", height = 520)
      )
    ),
    nav_panel(
      "Eğilim",
      card_body(
        selectInput("il_sec", "İl seç", choices = il_listesi,
                    selected = "İstanbul", width = 260),
        p(class = "text-muted small",
          "Kesik çizgi = 81 ilin medyanı (ülke ortası). Düz çizgi = seçili il."),
        plotOutput("egilim", height = 460)
      )
    ),
    nav_panel(
      "Veri",
      card_body(
        downloadButton("indir", "CSV indir", class = "btn-sm btn-primary mb-2"),
        DTOutput("tablo")
      )
    )
  )
)

# ============================= SUNUCU =========================================
server <- function(input, output, session) {

  # Gösterge değişince, o göstergenin mevcut yıllarıyla yıl listesini tazele
  observeEvent(input$gosterge, {
    yillar <- yillar_of(input$gosterge)
    updateSelectInput(inputId = "yil", choices = yillar, selected = max(yillar))
  })

  # Seçili gösterge-yıl dilimi (yil seçim kutusundan metin gelir -> integer)
  dilim <- reactive({
    req(input$yil)
    veri |> filter(gosterge_kodu == input$gosterge, yil == as.integer(input$yil))
  })

  ozet <- reactive({
    d <- dilim(); req(nrow(d) > 0)
    esitsizlik_ozeti(d, input$gosterge)
  })

  etiket <- reactive(names(gosterge_secenek)[gosterge_secenek == input$gosterge])
  birim  <- reactive(gosterge_meta$birim[gosterge_meta$gosterge_kodu == input$gosterge])

  # --- KPI çıktıları ----------------------------------------------------------
  output$kpi_oran <- renderText(sprintf("%.2f kat", ozet()$oran))
  output$kpi_iyi  <- renderText(sprintf("%s (%.1f)", ozet()$en_iyi$il,  ozet()$en_iyi$deger))
  output$kpi_kotu <- renderText(sprintf("%s (%.1f)", ozet()$en_kotu$il, ozet()$en_kotu$deger))

  output$harita_aciklama <- renderText({
    sprintf("%s — %s (%s). Koyu kırmızı iller daha kötü durumda.",
            etiket(), input$yil, birim())
  })

  # --- Harita (plotly: interaktif ama sf/leaflet/terra gerektirmez) -----------
  output$harita <- renderPlotly({
    req(nrow(dilim()) > 0)
    hd <- poligon |> left_join(dilim(), by = "il")
    yon <- gosterge_yonu(input$gosterge)
    yon_dir <- if (yon == "yuksek_iyi") -1 else 1   # kötü = koyu kırmızı

    g <- ggplot(hd, aes(long, lat, group = grup, fill = deger,
                        text = paste0(il, ": ", deger, " ", birim()))) +
      geom_polygon(color = "white", linewidth = 0.1) +
      scale_fill_distiller(palette = "YlOrRd", direction = yon_dir,
                           name = birim(), na.value = "grey85") +
      coord_fixed(1.3) +
      theme_void(base_size = 13)

    ggplotly(g, tooltip = "text") |>
      layout(margin = list(l = 0, r = 0, t = 0, b = 0))
  })

  # --- Sıralama (en iyi 10 + en kötü 10) --------------------------------------
  output$siralama <- renderPlot({
    df  <- dilim()
    req(nrow(df) > 0)
    yon <- gosterge_yonu(input$gosterge)
    sirali <- if (yon == "yuksek_iyi") arrange(df, deger) else arrange(df, desc(deger))
    # baştaki 10 = en kötü, sondaki 10 = en iyi
    sec <- bind_rows(
      head(sirali, 10) |> mutate(grup = "En kötü 10"),
      tail(sirali, 10) |> mutate(grup = "En iyi 10")
    )
    ggplot(sec, aes(x = reorder(il, deger), y = deger, fill = grup)) +
      geom_col() +
      coord_flip() +
      scale_fill_manual(values = c("En kötü 10" = KOTU_KIRMIZI, "En iyi 10" = IYI_YESIL)) +
      labs(x = NULL, y = sprintf("%s (%s)", etiket(), birim()),
           fill = NULL,
           title = sprintf("%s — %s", etiket(), input$yil)) +
      theme_minimal(base_size = 13) +
      theme(legend.position = "top")
  })

  # --- Eğilim (seçili il vs ülke medyanı) -------------------------------------
  output$egilim <- renderPlot({
    g <- input$gosterge
    ulusal <- veri |>
      filter(gosterge_kodu == g) |>
      group_by(yil) |>
      summarise(deger = median(deger), .groups = "drop")
    il_df <- veri |> filter(gosterge_kodu == g, il == input$il_sec)

    ggplot() +
      geom_line(data = ulusal, aes(yil, deger),
                linetype = "dashed", linewidth = 0.9, color = "grey50") +
      geom_line(data = il_df, aes(yil, deger),
                linewidth = 1.2, color = ANA_RENK) +
      geom_point(data = il_df, aes(yil, deger), size = 2.4, color = ANA_RENK) +
      scale_x_continuous(breaks = sort(unique(ulusal$yil))) +
      labs(x = NULL, y = sprintf("%s (%s)", etiket(), birim()),
           title = sprintf("%s — %s (mavi) vs ülke medyanı (kesik)",
                           etiket(), input$il_sec)) +
      theme_minimal(base_size = 13)
  })

  # --- Veri tablosu + indirme -------------------------------------------------
  genis_tablo <- reactive({
    req(input$yil)
    veri |>
      filter(yil == as.integer(input$yil)) |>
      select(il, gosterge, deger) |>
      pivot_wider(names_from = gosterge, values_from = deger) |>
      arrange(il)
  })

  output$tablo <- renderDT({
    datatable(genis_tablo(), rownames = FALSE,
              options = list(pageLength = 15, dom = "tip"))
  })

  output$indir <- downloadHandler(
    filename = function() sprintf("saglik_il_%s.csv", input$yil),
    content  = function(file) readr::write_excel_csv(genis_tablo(), file)
  )
}

shinyApp(ui, server)
