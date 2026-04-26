library(shiny)
library(shinydashboard)
library(leaflet)
library(plotly)
library(DT)
library(dplyr)
library(htmltools)

# ── Load & clean data ──────────────────────────────────────────────────────────
df_raw <- read.csv("clean_facilities-2026-04-25.csv", stringsAsFactors = FALSE)

bool_cols <- c("has_icu","has_emergency","has_surgery","has_lab",
               "has_pharmacy","has_xray","has_ambulance","has_obg")
for (col in bool_cols) {
  df_raw[[col]] <- toupper(trimws(df_raw[[col]])) == "TRUE"
}

df_raw <- df_raw[!is.na(df_raw$latitude) & !is.na(df_raw$longitude), ]

# ── CONFIDENCE SCORING ────────────────────────────────────────────────────────
# Four signals built from columns that are actually populated in this dataset

# Signal 1: Data Completeness (35%)
# Uses: description, email, yearEstablished, affiliated_staff_presence,
#       custom_logo_presence, recency_of_page_update, websites, phone
df_raw <- df_raw %>%
  mutate(
    completeness_score = round((
      (!is.na(description)  & trimws(description)  != "" & trimws(description)  != "null") * 1 +
        (!is.na(email)        & trimws(email)        != "" & trimws(email)        != "null") * 1 +
        (!is.na(yearEstablished) & trimws(as.character(yearEstablished)) != "" &
           trimws(as.character(yearEstablished)) != "null")                                  * 1 +
        (tolower(trimws(affiliated_staff_presence)) == "true")                               * 1 +
        (tolower(trimws(custom_logo_presence))      == "true")                               * 1 +
        (!is.na(recency_of_page_update) & trimws(recency_of_page_update) != "")             * 1 +
        (!is.na(websites)     & trimws(websites)     != "" & trimws(websites) != "[]")      * 1 +
        (!is.na(phone_numbers)& trimws(phone_numbers)!= "" & trimws(phone_numbers) != "[]") * 1
    ) / 8 * 100, 0)
  )

# Signal 2: Recency (25%)
# recency_of_page_update is well-populated with real dates
df_raw <- df_raw %>%
  mutate(
    days_since_update = suppressWarnings(
      as.numeric(Sys.Date() - as.Date(
        ifelse(is.na(recency_of_page_update) | trimws(recency_of_page_update) == "",
               NA, trimws(recency_of_page_update)),
        format = "%Y-%m-%d"
      ))
    ),
    recency_score = dplyr::case_when(
      !is.na(days_since_update) & days_since_update <= 180  ~ 100,
      !is.na(days_since_update) & days_since_update <= 365  ~  80,
      !is.na(days_since_update) & days_since_update <= 730  ~  55,
      !is.na(days_since_update) & days_since_update <= 1460 ~  30,
      !is.na(days_since_update) & days_since_update >  1460 ~  15,
      TRUE                                                   ~  10
    )
  )

# Signal 3: Internal Consistency (30%)
# Cross-checks capability claims against supporting infrastructure
df_raw <- df_raw %>%
  mutate(
    consistency_score = dplyr::case_when(
      has_surgery &  has_icu &  has_lab  ~ 100,  # fully supported
      has_surgery &  has_icu & !has_lab  ~  70,  # mostly supported
      has_surgery & !has_icu &  has_lab  ~  60,  # partially supported
      has_surgery & !has_icu & !has_lab  ~  10,  # contradiction
      !has_surgery                       ~  85   # no contradiction possible
    )
  )

# Signal 4: Online Presence (10%)
# post_metrics_most_recent_social_media_post_date is partially populated
df_raw <- df_raw %>%
  mutate(
    has_recent_post = !is.na(post_metrics_most_recent_social_media_post_date) &
      trimws(post_metrics_most_recent_social_media_post_date) != "",
    has_fb_link     = !is.na(facebookLink)  & trimws(facebookLink)  != "" & trimws(facebookLink)  != "null",
    has_tw_link     = !is.na(twitterLink)   & trimws(twitterLink)   != "" & trimws(twitterLink)   != "null",
    has_website     = !is.na(officialWebsite)& trimws(officialWebsite)!= ""& trimws(officialWebsite)!= "null",
    social_signals  = has_recent_post + has_fb_link + has_tw_link + has_website,
    social_score    = dplyr::case_when(
      social_signals >= 3 ~ 100,
      social_signals == 2 ~  80,
      social_signals == 1 ~  55,
      TRUE                ~  20
    )
  )

# Combined score
df_raw <- df_raw %>%
  mutate(
    confidence_score = round(
      completeness_score * 0.35 +
        recency_score      * 0.25 +
        consistency_score  * 0.30 +
        social_score       * 0.10,
      0
    ),
    confidence_label = dplyr::case_when(
      confidence_score >= 75 ~ "High",
      confidence_score >= 50 ~ "Medium",
      confidence_score >= 30 ~ "Low",
      TRUE                   ~ "Very Low"
    )
  )

df <- df_raw   # final enriched dataset

# ── Wilson score CI helper ────────────────────────────────────────────────────
wilson_ci <- function(successes, total, conf = 0.95) {
  if (total == 0) return(list(est=0, lo=0, hi=0))
  z     <- qnorm(1 - (1 - conf) / 2)
  p     <- successes / total
  ctr   <- (p + z^2/(2*total)) / (1 + z^2/total)
  margin<- (z * sqrt(p*(1-p)/total + z^2/(4*total^2))) / (1 + z^2/total)
  list(
    est = round(p   * 100, 1),
    lo  = round(max(0, ctr - margin) * 100, 1),
    hi  = round(min(1, ctr + margin) * 100, 1)
  )
}

# ── State-level ICU table with CIs (pre-computed) ─────────────────────────────
state_icu_ci <- df %>%
  filter(!is.na(address_stateOrRegion), address_stateOrRegion != "") %>%
  group_by(State = address_stateOrRegion) %>%
  summarise(
    total          = n(),
    icu            = sum(has_icu, na.rm=TRUE),
    avg_confidence = mean(confidence_score, na.rm=TRUE),
    .groups = "drop"
  ) %>%
  rowwise() %>%
  mutate(
    ci          = list(wilson_ci(icu, total)),
    icu_pct     = ci$est,
    ci_lo       = ci$lo,
    ci_hi       = ci$hi,
    # Widen interval when average confidence is low
    ci_adj      = (100 - avg_confidence) / 100 * 1.5,
    ci_lo_adj   = round(max(0,   ci_lo - ci_adj), 1),
    ci_hi_adj   = round(min(100, ci_hi + ci_adj), 1),
    ci_label    = paste0(icu_pct, "% [", ci_lo_adj, "–", ci_hi_adj, "%]")
  ) %>%
  ungroup()

# ── Dropdowns ─────────────────────────────────────────────────────────────────
all_states <- sort(unique(df$address_stateOrRegion[
  !is.na(df$address_stateOrRegion) & df$address_stateOrRegion != ""
]))
all_cities <- sort(unique(df$address_city[
  !is.na(df$address_city) & df$address_city != ""
]))

# ── Color palette ─────────────────────────────────────────────────────────────
C_NAVY   <- "#0F172A"
C_BLUE   <- "#1D4ED8"
C_SKY    <- "#38BDF8"
C_TEAL   <- "#0EA5E9"
C_CORAL  <- "#F43F5E"
C_SLATE  <- "#64748B"
C_LIGHT  <- "#94A3B8"
C_GREEN  <- "#10B981"
C_AMBER  <- "#F59E0B"
C_PURPLE <- "#8B5CF6"

# ── Plotly theme ──────────────────────────────────────────────────────────────
chart_layout <- function(p, xlab = "", ylab = "") {
  p %>% layout(
    paper_bgcolor = "rgba(0,0,0,0)",
    plot_bgcolor  = "rgba(0,0,0,0)",
    font   = list(color = C_SLATE, family = "DM Sans, Helvetica Neue, sans-serif", size = 11),
    xaxis  = list(
      title     = list(text = xlab, font = list(color = C_LIGHT, size = 11)),
      gridcolor = "#F1F5F9", zerolinecolor = "#E2E8F0",
      tickfont  = list(color = C_LIGHT, size = 11)
    ),
    yaxis  = list(
      title     = list(text = ylab, font = list(color = C_LIGHT, size = 11)),
      gridcolor = "#F1F5F9", zerolinecolor = "#E2E8F0",
      tickfont  = list(color = C_LIGHT, size = 11)
    ),
    margin = list(t = 16, b = 50, l = 55, r = 20),
    legend = list(font = list(color = C_SLATE, size = 11))
  ) %>%
    config(displayModeBar = FALSE)
}

# ── Confidence badge HTML helper ───────────────────────────────────────────────
conf_badge <- function(label) {
  dplyr::case_when(
    label == "High"     ~
      "<span style='background:#10B981;color:#fff;padding:2px 8px;border-radius:4px;font-size:10px;font-weight:600;'>HIGH</span>",
    label == "Medium"   ~
      "<span style='background:#F59E0B;color:#fff;padding:2px 8px;border-radius:4px;font-size:10px;font-weight:600;'>MED</span>",
    label == "Low"      ~
      "<span style='background:#F43F5E;color:#fff;padding:2px 8px;border-radius:4px;font-size:10px;font-weight:600;'>LOW</span>",
    TRUE                ~
      "<span style='background:#94A3B8;color:#fff;padding:2px 8px;border-radius:4px;font-size:10px;font-weight:600;'>?</span>"
  )
}

# ── Risk badge HTML helper ─────────────────────────────────────────────────────
risk_badge <- function(r) {
  dplyr::case_when(
    r == "Critical Desert" ~
      "<span style='background:#7F1D1D;color:#fff;padding:2px 7px;border-radius:4px;font-size:10px;font-weight:600;'>CRITICAL</span>",
    r == "High Risk" ~
      "<span style='background:#F43F5E;color:#fff;padding:2px 7px;border-radius:4px;font-size:10px;font-weight:600;'>HIGH</span>",
    r == "Moderate Risk" ~
      "<span style='background:#F59E0B;color:#fff;padding:2px 7px;border-radius:4px;font-size:10px;font-weight:600;'>MOD</span>",
    TRUE ~
      "<span style='background:#10B981;color:#fff;padding:2px 7px;border-radius:4px;font-size:10px;font-weight:600;'>LOW</span>"
  )
}

# ── SERVER ────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {
  
  # ── Filter mode ──────────────────────────────────────────────────────────────
  filter_mode <- reactive({
    if (is.null(input$filter_mode)) "state" else input$filter_mode
  })
  
  observeEvent(filter_mode(), {
    mode <- filter_mode()
    session$sendCustomMessage("update_filter_ui", mode)
    if (mode == "state") {
      updateSelectInput(session, "location_filter",
                        choices  = c("All States / Regions", all_states),
                        selected = "All States / Regions")
    } else {
      updateSelectInput(session, "location_filter",
                        choices  = c("All Cities", all_cities),
                        selected = "All Cities")
    }
  }, ignoreNULL = FALSE)
  
  # ── Filtered dataset — drives everything ─────────────────────────────────────
  filtered_df <- reactive({
    sel  <- input$location_filter
    mode <- filter_mode()
    if (mode == "state") {
      if (is.null(sel) || sel == "All States / Regions") df
      else df[df$address_stateOrRegion == sel, ]
    } else {
      if (is.null(sel) || sel == "All Cities") df
      else df[df$address_city == sel, ]
    }
  })
  
  # ── Location label ────────────────────────────────────────────────────────────
  location_label <- reactive({
    sel  <- input$location_filter
    mode <- filter_mode()
    if (mode == "state") {
      if (is.null(sel) || sel == "All States / Regions") "India · All States / Regions"
      else paste0("State / Region: ", sel)
    } else {
      if (is.null(sel) || sel == "All Cities") "India · All Cities"
      else paste0("City: ", sel)
    }
  })
  
  output$strip_location_map      <- renderText(location_label())
  output$strip_location_overview <- renderText(location_label())
  
  # ── KPIs ─────────────────────────────────────────────────────────────────────
  output$kpi_total <- renderText({
    format(nrow(filtered_df()), big.mark=",")
  })
  output$kpi_icu <- renderText({
    format(sum(filtered_df()$has_icu, na.rm=TRUE), big.mark=",")
  })
  output$kpi_emergency <- renderText({
    format(sum(filtered_df()$has_emergency, na.rm=TRUE), big.mark=",")
  })
  output$kpi_flagged <- renderText({
    d <- filtered_df()
    format(sum(d$has_surgery & !d$has_icu & !d$has_lab, na.rm=TRUE), big.mark=",")
  })
  
  # ── ICU bar chart with confidence intervals ───────────────────────────────────
  output$bar_icu <- renderPlotly({
    sel  <- input$location_filter
    mode <- filter_mode()
    d    <- filtered_df()
    
    is_filtered <- !(is.null(sel) ||
                       sel == "All States / Regions" ||
                       sel == "All Cities")
    
    if (is_filtered && mode == "state") {
      grp     <- d %>% filter(!is.na(address_city), address_city != "") %>%
        group_by(Location = address_city)
      x_label <- paste0("ICU Availability (%) · Cities in ", sel)
    } else if (is_filtered && mode == "city") {
      grp     <- d %>% filter(!is.na(facilityTypeId), facilityTypeId != "") %>%
        group_by(Location = facilityTypeId)
      x_label <- paste0("ICU Availability (%) · Facility Types in ", sel)
    } else {
      grp     <- d %>% filter(!is.na(address_stateOrRegion), address_stateOrRegion != "") %>%
        group_by(Location = address_stateOrRegion)
      x_label <- "ICU Availability (%) · Top 15 States / Regions"
    }
    
    d_sum <- grp %>%
      summarise(
        total          = n(),
        icu            = sum(has_icu, na.rm=TRUE),
        avg_confidence = mean(confidence_score, na.rm=TRUE),
        .groups = "drop"
      ) %>%
      arrange(desc(total)) %>%
      slice_head(n=15) %>%
      rowwise() %>%
      mutate(
        ci        = list(wilson_ci(icu, total)),
        icu_pct   = ci$est,
        ci_lo     = ci$lo,
        ci_hi     = ci$hi,
        ci_adj    = (100 - avg_confidence) / 100 * 1.5,
        ci_lo_adj = round(max(0,   ci_lo - ci_adj), 1),
        ci_hi_adj = round(min(100, ci_hi + ci_adj), 1),
        err_lo    = icu_pct - ci_lo_adj,
        err_hi    = ci_hi_adj - icu_pct,
        hover_txt = paste0(
          "<b>", Location, "</b><br>",
          "ICU: <b>", icu_pct, "%</b><br>",
          "95% CI: [", ci_lo_adj, "% – ", ci_hi_adj, "%]<br>",
          "Data confidence: <b>", round(avg_confidence), "/100</b><br>",
          icu, " of ", total, " facilities"
        )
      ) %>%
      ungroup() %>%
      arrange(icu_pct)
    
    if (nrow(d_sum) == 0) return(plotly_empty())
    
    plot_ly(d_sum,
            x           = ~icu_pct,
            y           = ~reorder(Location, icu_pct),
            type        = "bar",
            orientation = "h",
            marker      = list(
              color      = ~icu_pct,
              colorscale = list(c(0, C_CORAL), c(0.4, C_AMBER), c(1, C_GREEN)),
              showscale  = FALSE,
              line       = list(color="rgba(0,0,0,0)", width=0)
            ),
            text         = ~paste0(icu_pct, "%"),
            textposition = "outside",
            textfont     = list(color = C_LIGHT, size = 10),
            hovertemplate = "%{customdata}<extra></extra>",
            customdata    = ~hover_txt
    ) %>%
      chart_layout(xlab = x_label, ylab = "") %>%
      layout(xaxis = list(
        ticksuffix = "%",
        range      = c(0, max(d_sum$icu_pct, na.rm=TRUE) * 1.35)
      ))
  })
  
  # ── Facility type donut ───────────────────────────────────────────────────────
  output$bar_type <- renderPlotly({
    d <- filtered_df() %>%
      filter(!is.na(facilityTypeId), facilityTypeId != "") %>%
      count(Type = facilityTypeId, sort=TRUE) %>%
      slice_head(n=6)
    
    if (nrow(d) == 0) return(plotly_empty())
    
    plot_ly(d, labels=~Type, values=~n, type="pie", hole=0.48,
            marker = list(
              colors = c(C_BLUE, C_TEAL, C_GREEN, C_AMBER, C_CORAL, C_PURPLE),
              line   = list(color="#FFFFFF", width=2)
            ),
            textinfo       = "label+percent",
            insidetextfont = list(color="#FFFFFF"),
            textfont       = list(size=11),
            hovertemplate  = "<b>%{label}</b><br>%{value} facilities (%{percent})<extra></extra>"
    ) %>%
      chart_layout() %>%
      layout(showlegend=FALSE)
  })
  
  # ── Capability coverage ───────────────────────────────────────────────────────
  output$bar_capability <- renderPlotly({
    d <- filtered_df()
    cap_df <- data.frame(
      Capability = c("Emergency","Lab","Surgery","Pharmacy","ICU","X-Ray","Ambulance","OBG"),
      Count = c(
        sum(d$has_emergency, na.rm=TRUE), sum(d$has_lab,       na.rm=TRUE),
        sum(d$has_surgery,   na.rm=TRUE), sum(d$has_pharmacy,  na.rm=TRUE),
        sum(d$has_icu,       na.rm=TRUE), sum(d$has_xray,      na.rm=TRUE),
        sum(d$has_ambulance, na.rm=TRUE), sum(d$has_obg,       na.rm=TRUE)
      )
    ) %>% arrange(desc(Count))
    
    bar_colors <- ifelse(cap_df$Capability %in% c("ICU","Surgery"), C_CORAL, C_TEAL)
    
    plot_ly(cap_df,
            x = ~reorder(Capability, -Count), y = ~Count,
            type   = "bar",
            marker = list(color=bar_colors, line=list(color="rgba(0,0,0,0)", width=0)),
            hovertemplate = "<b>%{x}</b><br>%{y} facilities<extra></extra>"
    ) %>%
      chart_layout(xlab="", ylab="Facility Count")
  })
  
  # ── Leaflet facility map ──────────────────────────────────────────────────────
  output$map_facilities <- renderLeaflet({
    d          <- filtered_df()
    pal_colors <- ifelse(d$has_icu, C_TEAL, C_CORAL)
    
    popup_html <- paste0(
      "<b>", htmlEscape(ifelse(is.na(d$name),"Unknown",d$name)), "</b><br>",
      "<span style='color:#94A3B8;font-size:11px;'>",
      htmlEscape(ifelse(is.na(d$facilityTypeId),"",d$facilityTypeId)),
      "</span><br><br>",
      "<b>City:</b> ", htmlEscape(ifelse(is.na(d$address_city),"—",d$address_city)), "<br>",
      "<b>State / Region:</b> ", htmlEscape(ifelse(is.na(d$address_stateOrRegion),"—",d$address_stateOrRegion)), "<br><br>",
      "<b>ICU:</b> ", ifelse(d$has_icu,
                             "<span style='color:#10B981;font-weight:600;'>✓ Yes</span>",
                             "<span style='color:#F43F5E;font-weight:600;'>✗ No</span>"), "  ",
      "<b>Surgery:</b> ",   ifelse(d$has_surgery,   "✓","✗"), "  ",
      "<b>Lab:</b> ",       ifelse(d$has_lab,       "✓","✗"), "  ",
      "<b>Emergency:</b> ", ifelse(d$has_emergency, "✓","✗"), "<br><br>",
      "<b>Data Confidence:</b> ",
      conf_badge(d$confidence_label), "  ",
      "<span style='color:#94A3B8;font-size:11px;'>", d$confidence_score, "/100</span>"
    )
    
    sel         <- input$location_filter
    is_filtered <- !(is.null(sel) ||
                       sel == "All States / Regions" ||
                       sel == "All Cities")
    
    m <- leaflet(d, options=leafletOptions(preferCanvas=TRUE)) %>%
      addProviderTiles("CartoDB.Positron", options=tileOptions(opacity=1)) %>%
      addCircleMarkers(
        lng=~longitude, lat=~latitude,
        radius      = 5,
        color       = pal_colors, fillColor = pal_colors,
        fillOpacity = 0.7, opacity=1, weight=1.5,
        popup       = popup_html,
        clusterOptions = markerClusterOptions(
          showCoverageOnHover=FALSE,
          zoomToBoundsOnClick=TRUE,
          maxClusterRadius=45,
          iconCreateFunction=JS("
            function(cluster) {
              var count = cluster.getChildCount();
              var size  = count < 100 ? 32 : count < 500 ? 40 : 48;
              return L.divIcon({
                html: '<div style=\"background:#1D4ED8;border-radius:50%;width:'+size+'px;height:'+size+'px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:12px;font-weight:700;font-family:DM Sans,sans-serif;border:2.5px solid #fff;box-shadow:0 2px 10px rgba(29,78,216,0.35);\">'+ count +'</div>',
                className:'', iconSize:[size,size]
              });
            }
          ")
        )
      )
    
    if (is_filtered && nrow(d) > 0) {
      m <- m %>% fitBounds(
        lng1=min(d$longitude,na.rm=TRUE), lat1=min(d$latitude,na.rm=TRUE),
        lng2=max(d$longitude,na.rm=TRUE), lat2=max(d$latitude,na.rm=TRUE)
      )
    } else {
      m <- m %>% setView(lng=80, lat=22, zoom=5)
    }
    m
  })
  
  # ── High risk table with confidence scores ────────────────────────────────────
  output$table_highrisk <- renderDT({
    d <- filtered_df() %>%
      filter(has_surgery==TRUE, has_icu==FALSE, has_lab==FALSE) %>%
      select(name, address_city, address_stateOrRegion, facilityTypeId,
             has_surgery, has_icu, has_lab, has_emergency,
             confidence_score, confidence_label,
             completeness_score, recency_score, consistency_score)
    
    colnames(d) <- c("Facility","City","State / Region","Type",
                     "Surgery","ICU","Lab","Emergency",
                     "Score","Confidence","Completeness","Recency","Consistency")
    
    yes <- "<span style='color:#10B981;font-weight:600;'>✓</span>"
    no  <- "<span style='color:#F43F5E;font-weight:600;'>✗</span>"
    fmt <- function(x) ifelse(x, yes, no)
    
    d$Surgery   <- fmt(d$Surgery)
    d$ICU       <- fmt(d$ICU)
    d$Lab       <- fmt(d$Lab)
    d$Emergency <- fmt(d$Emergency)
    d$Confidence<- conf_badge(d$Confidence)
    d$Score     <- paste0(d$Score, "/100")
    
    datatable(d,
              rownames  = FALSE,
              escape    = FALSE,
              filter    = "top",
              options   = list(
                pageLength = 15,
                scrollX    = TRUE,
                dom        = "ftip",
                language   = list(search="Search facilities..."),
                columnDefs = list(
                  list(className="dt-center", targets=4:12)
                )
              )
    )
  })
  
  # ── Confidence distribution chart ─────────────────────────────────────────────
  output$bar_confidence <- renderPlotly({
    d <- filtered_df() %>%
      count(confidence_label) %>%
      mutate(
        confidence_label = factor(
          confidence_label,
          levels = c("High","Medium","Low","Very Low")
        ),
        color = dplyr::case_when(
          confidence_label == "High"     ~ C_GREEN,
          confidence_label == "Medium"   ~ C_AMBER,
          confidence_label == "Low"      ~ C_CORAL,
          TRUE                           ~ "#94A3B8"
        )
      ) %>%
      arrange(confidence_label)
    
    if (nrow(d) == 0) return(plotly_empty())
    
    plot_ly(d,
            x    = ~confidence_label, y = ~n,
            type = "bar",
            marker = list(
              color = ~color,
              line  = list(color="rgba(0,0,0,0)", width=0)
            ),
            text         = ~format(n, big.mark=","),
            textposition = "outside",
            textfont     = list(color=C_SLATE, size=12, family="DM Sans, sans-serif"),
            hovertemplate = "<b>%{x}</b><br>%{y} facilities<extra></extra>"
    ) %>%
      chart_layout(xlab="Confidence Level", ylab="Facility Count") %>%
      layout(yaxis = list(range = c(0, max(d$n) * 1.15)))
  })
  
  # ── Average confidence by state chart ────────────────────────────────────────
  output$bar_conf_state <- renderPlotly({
    d <- filtered_df() %>%
      filter(!is.na(address_stateOrRegion), address_stateOrRegion != "") %>%
      group_by(State = address_stateOrRegion) %>%
      summarise(
        avg_conf = round(mean(confidence_score, na.rm=TRUE), 1),
        total    = n(),
        .groups  = "drop"
      ) %>%
      arrange(desc(total)) %>%
      slice_head(n=15) %>%
      arrange(avg_conf)
    
    if (nrow(d) == 0) return(plotly_empty())
    
    plot_ly(d,
            x           = ~avg_conf,
            y           = ~reorder(State, avg_conf),
            type        = "bar",
            orientation = "h",
            marker      = list(
              color      = ~avg_conf,
              colorscale = list(c(0, C_CORAL), c(0.5, C_AMBER), c(1, C_GREEN)),
              showscale  = FALSE,
              line       = list(color="rgba(0,0,0,0)", width=0)
            ),
            text         = ~paste0(avg_conf, "/100"),
            textposition = "outside",
            textfont     = list(color=C_LIGHT, size=11),
            hovertemplate = "<b>%{y}</b><br>Avg confidence: <b>%{x}/100</b><br>%{customdata} facilities<extra></extra>",
            customdata    = ~total
    ) %>%
      chart_layout(xlab="Average Data Confidence Score", ylab="") %>%
      layout(xaxis = list(range=c(0, 110)))
  })
  
  # ── Specialty bar ─────────────────────────────────────────────────────────────
  output$bar_specialty <- renderPlotly({
    d <- filtered_df()
    all_s <- unlist(lapply(d$specialties, function(x) {
      x <- gsub('\\[|\\]|"','',x)
      trimws(unlist(strsplit(x,",")))
    }))
    all_s <- all_s[all_s != "" & !is.na(all_s)]
    if (length(all_s) == 0) return(plotly_empty())
    
    spec <- as.data.frame(sort(table(all_s), decreasing=TRUE)[1:min(15,length(unique(all_s)))])
    colnames(spec) <- c("Specialty","Count")
    spec <- spec[order(spec$Count),]
    
    plot_ly(spec,
            x=~Count, y=~reorder(Specialty, Count),
            type="bar", orientation="h",
            marker=list(color=C_TEAL, line=list(color="rgba(0,0,0,0)", width=0)),
            hovertemplate="<b>%{y}</b><br>%{x} facilities<extra></extra>"
    ) %>%
      chart_layout(xlab="Facility Count", ylab="")
  })
  
  # ── Operator pie ──────────────────────────────────────────────────────────────
  output$pie_operator <- renderPlotly({
    d <- filtered_df() %>%
      filter(
        !is.na(operatorTypeId),
        operatorTypeId != "",
        tolower(trimws(operatorTypeId)) != "null"
      ) %>%
      count(Operator=operatorTypeId, sort=TRUE)
    
    if (nrow(d) == 0) return(plotly_empty())
    
    plot_ly(d, labels=~Operator, values=~n, type="pie", hole=0.45,
            marker=list(
              colors=c(C_BLUE, C_TEAL, C_GREEN, C_AMBER),
              line=list(color="#FFFFFF", width=2)
            ),
            textinfo="label+percent",
            insidetextfont=list(color="#FFFFFF", size=12),
            hovertemplate="<b>%{label}</b><br>%{value} facilities<extra></extra>"
    ) %>%
      chart_layout() %>%
      layout(showlegend=FALSE)
  })
  
  # ── CRISIS MAP ────────────────────────────────────────────────────────────────
  pin_scores <- reactive({
    filtered_df() %>%
      filter(
        !is.na(address_zipOrPostcode),
        address_zipOrPostcode != "",
        !is.na(latitude), !is.na(longitude)
      ) %>%
      group_by(
        pin   = address_zipOrPostcode,
        state = address_stateOrRegion,
        city  = address_city
      ) %>%
      summarise(
        facility_count  = n(),
        icu_count       = sum(has_icu,        na.rm=TRUE),
        surgery_count   = sum(has_surgery,    na.rm=TRUE),
        emergency_count = sum(has_emergency,  na.rm=TRUE),
        lab_count       = sum(has_lab,        na.rm=TRUE),
        avg_confidence  = mean(confidence_score, na.rm=TRUE),
        lat             = mean(latitude,      na.rm=TRUE),
        lng             = mean(longitude,     na.rm=TRUE),
        .groups = "drop"
      ) %>%
      mutate(
        icu_pct       = icu_count       / facility_count,
        surgery_pct   = surgery_count   / facility_count,
        emergency_pct = emergency_count / facility_count,
        lab_pct       = lab_count       / facility_count,
        # Desert score: higher = worse coverage = bigger desert (0-100)
        # pcts are 0-1 fractions so multiply weights by 100 directly
        desert_raw    = 100 - (
          (icu_pct * 40) + (surgery_pct * 25) +
            (emergency_pct * 20) + (lab_pct * 15)
        ) * 100,
        # Clamp raw score to 0-100 before penalty
        desert_raw    = pmax(0, pmin(100, desert_raw)),
        # Widen slightly for low-confidence PINs
        conf_penalty  = (100 - avg_confidence) / 100 * 3,
        desert_score  = round(pmin(100, desert_raw + conf_penalty), 1),
        risk_level    = dplyr::case_when(
          desert_score >= 90 ~ "Critical Desert",
          desert_score >= 75 ~ "High Risk",
          desert_score >= 50 ~ "Moderate Risk",
          TRUE               ~ "Low Risk"
        )
      ) %>%
      arrange(desc(desert_score))
  })
  
  output$crisis_pin_count    <- renderText(format(nrow(pin_scores()), big.mark=","))
  output$crisis_zero_icu     <- renderText(format(sum(pin_scores()$icu_count == 0), big.mark=","))
  output$crisis_desert_count <- renderText(format(sum(pin_scores()$desert_score >= 75), big.mark=","))
  output$crisis_avg_score    <- renderText(paste0(round(mean(pin_scores()$desert_score, na.rm=TRUE),1),"/100"))
  
  output$crisis_map <- renderLeaflet({
    d   <- pin_scores()
    pal <- leaflet::colorNumeric(
      palette  = c("#10B981","#F59E0B","#F43F5E","#7F1D1D"),
      domain   = c(0, 100),
      na.color = "#CBD5E1"
    )
    
    popup_html <- paste0(
      "<b>PIN: ", htmlEscape(as.character(d$pin)), "</b><br>",
      "<b>", htmlEscape(ifelse(is.na(d$city),"",d$city)), "</b>  ",
      "<span style='color:#94A3B8;'>",
      htmlEscape(ifelse(is.na(d$state),"",d$state)), "</span><br><br>",
      "<b style='color:", ifelse(d$desert_score>=75,"#F43F5E","#10B981"), ";'>",
      "Desert Score: ", d$desert_score, "/100</b><br>",
      "<b>Risk: </b>", d$risk_level, "<br>",
      "<b>Data Confidence: </b>", round(d$avg_confidence,0), "/100<br><br>",
      "Facilities: <b>", d$facility_count, "</b><br>",
      "ICU: <b>", d$icu_count, "</b>  ",
      "Surgery: <b>", d$surgery_count, "</b>  ",
      "Emergency: <b>", d$emergency_count, "</b>"
    )
    
    leaflet(d, options=leafletOptions(preferCanvas=TRUE)) %>%
      addProviderTiles("CartoDB.Positron", options=tileOptions(opacity=1)) %>%
      addCircleMarkers(
        lng=~lng, lat=~lat,
        radius      = ~pmax(5, pmin(20, sqrt(facility_count) * 2.5)),
        color       = ~pal(desert_score), fillColor=~pal(desert_score),
        fillOpacity = 0.75, opacity=1, weight=1.5,
        popup       = popup_html
      ) %>%
      addLegend(
        position = "bottomright",
        pal      = pal,
        values   = ~desert_score,
        title    = "Desert Score",
        opacity  = 0.85
      ) %>%
      setView(lng=80, lat=22, zoom=5)
  })
  
  output$desert_table <- renderDT({
    d <- pin_scores() %>%
      head(20) %>%
      select(pin, city, state, facility_count, icu_count,
             avg_confidence, desert_score, risk_level)
    
    colnames(d) <- c("PIN","City","State","Facilities","ICU","Confidence","Score","Risk")
    
    d$Risk       <- risk_badge(d$Risk)
    d$Score      <- paste0(d$Score, "/100")
    d$Confidence <- paste0(round(d$Confidence,0), "/100")
    
    datatable(d,
              rownames = FALSE, escape = FALSE,
              options  = list(
                pageLength    = 20,
                dom           = "t",
                scrollY       = "460px",
                scrollX       = TRUE,
                scrollCollapse= TRUE,
                fixedHeader   = TRUE,
                autoWidth     = FALSE,
                columnDefs    = list(
                  list(className = "dt-center", targets = c(3,4,5,6,7)),
                  list(width = "110px", targets = 0),
                  list(width = "100px", targets = 1),
                  list(width = "110px", targets = 2),
                  list(width = "70px",  targets = 3),
                  list(width = "50px",  targets = 4),
                  list(width = "80px",  targets = 5),
                  list(width = "70px",  targets = 6),
                  list(width = "60px",  targets = 7)
                )
              )
    )
  })
}