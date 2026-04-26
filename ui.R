library(shiny)
library(shinydashboard)
library(leaflet)
library(plotly)
library(DT)

ui <- dashboardPage(
  skin = "black",
  
  # ── HEADER ────────────────────────────────────────────────────────────────────
  dashboardHeader(
    title = tags$span(
      tags$span(style = "
        font-family: 'DM Sans', 'Helvetica Neue', sans-serif;
        font-size: 17px;
        font-weight: 700;
        letter-spacing: 2.5px;
        color: #ffffff;
      ", "VERI"),
      tags$span(style = "
        font-family: 'DM Sans', 'Helvetica Neue', sans-serif;
        font-size: 17px;
        font-weight: 300;
        letter-spacing: 2.5px;
        color: #7DD3FC;
      ", "CARE")
    )
  ),
  
  # ── SIDEBAR ───────────────────────────────────────────────────────────────────
  dashboardSidebar(
    tags$style(HTML("
      @import url('https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600;700&display=swap');

      .main-sidebar {
        background-color: #0F172A !important;
        border-right: 1px solid #1E293B !important;
      }
      .sidebar-menu > li > a {
        color: #94A3B8 !important;
        font-family: 'DM Sans', sans-serif !important;
        font-size: 13px !important;
        font-weight: 500 !important;
        letter-spacing: 0.3px !important;
        padding: 11px 20px !important;
        border-left: 3px solid transparent !important;
        transition: all 0.15s ease !important;
      }
      .sidebar-menu > li.active > a,
      .sidebar-menu > li > a:hover {
        color: #F0F9FF !important;
        background: rgba(125, 211, 252, 0.08) !important;
        border-left: 3px solid #38BDF8 !important;
      }
      .sidebar-menu > li > a > .fa {
        color: #38BDF8 !important;
        width: 18px !important;
      }
      .sidebar { padding-top: 6px; }
      .sidebar-menu > li > a > .fa-angle-left { color: #475569 !important; }
      .filter-section-label {
        color: #475569;
        font-family: 'DM Sans', sans-serif;
        font-size: 10px;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 1.2px;
        padding: 0 20px;
        margin-bottom: 8px;
        display: block;
      }
      .toggle-btn {
        flex: 1;
        padding: 7px 4px;
        font-size: 11px;
        font-weight: 600;
        font-family: 'DM Sans', sans-serif;
        border-radius: 6px;
        cursor: pointer;
        transition: all 0.15s ease;
        letter-spacing: 0.3px;
      }
      .toggle-active {
        background: #38BDF8;
        color: #0F172A;
        border: none;
      }
      .toggle-inactive {
        background: transparent;
        color: #64748B;
        border: 1px solid #1E293B;
      }
      .selectize-input {
        background: #1E293B !important;
        color: #E2E8F0 !important;
        border: 1px solid #334155 !important;
        border-radius: 7px !important;
        font-family: 'DM Sans', sans-serif !important;
        font-size: 12px !important;
        box-shadow: none !important;
      }
      .selectize-dropdown {
        background: #1E293B !important;
        color: #E2E8F0 !important;
        border: 1px solid #334155 !important;
        font-family: 'DM Sans', sans-serif !important;
        font-size: 12px !important;
      }
      .selectize-dropdown .option:hover,
      .selectize-dropdown .option.active {
        background: #334155 !important;
        color: #F0F9FF !important;
      }
      .selectize-dropdown .option { color: #E2E8F0 !important; }
      .selectize-input input { color: #E2E8F0 !important; }
      .selectize-input.full .item { color: #E2E8F0 !important; }
      .sidebar-divider {
        border: none;
        border-top: 1px solid #1E293B;
        margin: 12px 20px;
      }
    ")),
    
    sidebarMenu(
      id = "tabs",
      menuItem("Overview",     tabName = "overview",  icon = icon("chart-bar")),
      menuItem("Facility Map", tabName = "map",       icon = icon("map")),
      menuItem("Crisis Map",   tabName = "crisis",    icon = icon("fire")),
      menuItem("High Risk",    tabName = "highrisk",  icon = icon("triangle-exclamation")),
      menuItem("Specialties",  tabName = "specialty", icon = icon("stethoscope")),
      
      tags$hr(class = "sidebar-divider"),
      
      tags$span(class = "filter-section-label", "Map Filter"),
      tags$div(
        style = "padding: 0 16px; margin-bottom: 10px;",
        tags$div(
          style = "display: flex; gap: 6px; margin-bottom: 10px;",
          tags$button("State / Region", id = "btn_state",
                      class = "toggle-btn toggle-active",
                      onclick = "Shiny.setInputValue('filter_mode', 'state', {priority: 'event'})"
          ),
          tags$button("City", id = "btn_city",
                      class = "toggle-btn toggle-inactive",
                      onclick = "Shiny.setInputValue('filter_mode', 'city', {priority: 'event'})"
          )
        ),
        selectInput("location_filter", label = NULL,
                    choices = NULL, selected = NULL, width = "100%")
      ),
      
      tags$script(HTML("
        Shiny.addCustomMessageHandler('update_filter_ui', function(mode) {
          var bs = document.getElementById('btn_state');
          var bc = document.getElementById('btn_city');
          if (mode === 'state') {
            bs.className = 'toggle-btn toggle-active';
            bc.className = 'toggle-btn toggle-inactive';
          } else {
            bc.className = 'toggle-btn toggle-active';
            bs.className = 'toggle-btn toggle-inactive';
          }
        });
      "))
    )
  ),
  
  # ── BODY ──────────────────────────────────────────────────────────────────────
  dashboardBody(
    
    tags$head(
      tags$link(rel = "stylesheet",
                href = "https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600;700&display=swap"),
      tags$style(HTML("

        /* ── Global ── */
        *, body, .wrapper {
          font-family: 'DM Sans', 'Helvetica Neue', sans-serif !important;
        }
        body, .wrapper         { background-color: #F8FAFC !important; color: #0F172A !important; }
        .content-wrapper       { background-color: #F8FAFC !important; }
        .content               { padding: 20px 24px !important; }

        /* ── Header ── */
        .main-header .navbar   { background-color: #0F172A !important; border-bottom: none !important; box-shadow: 0 1px 3px rgba(0,0,0,0.3) !important; }
        .main-header .logo     { background-color: #0F172A !important; border-bottom: none !important; }
        .main-header .navbar .sidebar-toggle { color: #64748B !important; }
        .main-header .navbar .sidebar-toggle:hover { color: #E2E8F0 !important; background: transparent !important; }

        /* ── Boxes ── */
        .box {
          background: #FFFFFF !important;
          border: 1px solid #E2E8F0 !important;
          border-top: none !important;
          border-radius: 12px !important;
          box-shadow: 0 1px 4px rgba(15,23,42,0.06) !important;
          overflow: hidden !important;
        }
        .box-header {
          background: #FFFFFF !important;
          color: #0F172A !important;
          border-bottom: 1px solid #F1F5F9 !important;
          padding: 14px 18px !important;
          font-size: 12px !important;
          font-weight: 600 !important;
          letter-spacing: 0.6px !important;
          text-transform: uppercase !important;
          color: #64748B !important;
        }
        .box-body { padding: 16px !important; }

        /* ── KPI Cards ── */
        .kpi-card {
          background: #FFFFFF;
          border: 1px solid #E2E8F0;
          border-radius: 12px;
          padding: 20px 22px;
          margin-bottom: 20px;
          box-shadow: 0 1px 4px rgba(15,23,42,0.06);
          display: flex;
          align-items: center;
          gap: 16px;
        }
        .kpi-icon {
          width: 48px; height: 48px;
          border-radius: 10px;
          display: flex; align-items: center; justify-content: center;
          font-size: 20px; flex-shrink: 0;
        }
        .kpi-icon-blue  { background: #EFF6FF; color: #1D4ED8; }
        .kpi-icon-sky   { background: #F0F9FF; color: #0284C7; }
        .kpi-icon-coral { background: #FFF1F2; color: #E11D48; }
        .kpi-icon-slate { background: #F8FAFC; color: #475569; }
        .kpi-value { font-size: 26px; font-weight: 700; color: #0F172A; line-height: 1; }
        .kpi-label { font-size: 11px; color: #94A3B8; margin-top: 5px; font-weight: 500; letter-spacing: 0.4px; text-transform: uppercase; }
        .kpi-border-blue  { border-top: 2px solid #3B82F6 !important; }
        .kpi-border-sky   { border-top: 2px solid #38BDF8 !important; }
        .kpi-border-coral { border-top: 2px solid #F43F5E !important; }
        .kpi-border-slate { border-top: 2px solid #CBD5E1 !important; }

        /* ── Page header strip ── */
        .page-header-strip {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 20px;
          padding-bottom: 16px;
          border-bottom: 1px solid #E2E8F0;
        }
        .page-header-strip h4 {
          margin: 0;
          font-size: 18px;
          font-weight: 700;
          color: #0F172A;
          letter-spacing: -0.3px;
        }
        .page-header-strip p {
          margin: 3px 0 0;
          font-size: 12px;
          color: #94A3B8;
          font-weight: 400;
        }
        .page-tag {
          background: #EFF6FF;
          color: #1D4ED8;
          font-size: 11px;
          font-weight: 600;
          padding: 5px 12px;
          border-radius: 20px;
          letter-spacing: 0.3px;
        }

        /* ── Alert banner ── */
        .alert-coral {
          background: #FFF1F2;
          border: 1px solid #FECDD3;
          border-left: 3px solid #F43F5E;
          border-radius: 8px;
          padding: 12px 16px;
          margin-bottom: 18px;
          color: #9F1239;
          font-size: 13px;
          font-weight: 400;
        }

        /* ── DataTable ── */
        .dataTables_wrapper   { color: #0F172A !important; font-family: 'DM Sans', sans-serif !important; }
        table.dataTable        { background: #FFFFFF !important; color: #0F172A !important; border-collapse: collapse !important; font-size: 13px !important; }
        table.dataTable thead th {
          background: #F8FAFC !important;
          color: #64748B !important;
          border-bottom: 1px solid #E2E8F0 !important;
          font-size: 10px !important;
          text-transform: uppercase !important;
          letter-spacing: 0.8px !important;
          padding: 10px 14px !important;
          font-weight: 600 !important;
        }
        table.dataTable tbody tr           { background: #FFFFFF !important; }
        table.dataTable tbody tr:nth-child(even) { background: #FAFAFA !important; }
        table.dataTable tbody tr:hover     { background: #F0F9FF !important; }
        table.dataTable tbody td           { border-bottom: 1px solid #F1F5F9 !important; padding: 10px 14px !important; color: #334155 !important; }
        .dataTables_filter input, .dataTables_length select {
          background: #F8FAFC !important;
          color: #0F172A !important;
          border: 1px solid #E2E8F0 !important;
          border-radius: 7px !important;
          padding: 5px 10px !important;
          font-family: 'DM Sans', sans-serif !important;
          font-size: 12px !important;
        }
        .dataTables_info, .dataTables_paginate { color: #94A3B8 !important; font-size: 12px !important; }
        .paginate_button                   { color: #64748B !important; border-radius: 6px !important; font-size: 12px !important; }
        .paginate_button.current, .paginate_button.current:hover {
          background: #1D4ED8 !important; color: #FFFFFF !important; border: none !important;
        }
        .paginate_button:hover { background: #EFF6FF !important; color: #1D4ED8 !important; border: none !important; }

        /* ── Leaflet popup ── */
        .leaflet-popup-content-wrapper {
          background: #FFFFFF !important;
          color: #0F172A !important;
          border-radius: 10px !important;
          border: 1px solid #E2E8F0 !important;
          box-shadow: 0 8px 24px rgba(15,23,42,0.12) !important;
          font-family: 'DM Sans', sans-serif !important;
        }
        .leaflet-popup-tip { background: #FFFFFF !important; }
        .leaflet-popup-content b { color: #1D4ED8; }
        .leaflet-popup-content   { font-size: 13px !important; line-height: 1.6 !important; }
      "))
    ),
    
    tabItems(
      
      # ── OVERVIEW ──────────────────────────────────────────────────────────────
      tabItem(tabName = "overview",
              tags$div(class = "page-header-strip",
                       tags$div(
                         tags$h4("Healthcare Facility Overview"),
                         tags$p(textOutput("strip_location_overview", inline = TRUE))
                       ),
                       tags$span(class = "page-tag", "VeriCare Intelligence")
              ),
              
              fluidRow(
                column(3, tags$div(class = "kpi-card kpi-border-blue",
                                   tags$div(class = "kpi-icon kpi-icon-blue", icon("hospital")),
                                   tags$div(tags$div(class = "kpi-value", textOutput("kpi_total")),
                                            tags$div(class = "kpi-label", "Total Facilities"))
                )),
                column(3, tags$div(class = "kpi-card kpi-border-sky",
                                   tags$div(class = "kpi-icon kpi-icon-sky", icon("bed-pulse")),
                                   tags$div(tags$div(class = "kpi-value", textOutput("kpi_icu")),
                                            tags$div(class = "kpi-label", "Facilities with ICU"))
                )),
                column(3, tags$div(class = "kpi-card kpi-border-coral",
                                   tags$div(class = "kpi-icon kpi-icon-coral", icon("triangle-exclamation")),
                                   tags$div(tags$div(class = "kpi-value", textOutput("kpi_flagged")),
                                            tags$div(class = "kpi-label", "Flagged Contradictions"))
                )),
                column(3, tags$div(class = "kpi-card kpi-border-slate",
                                   tags$div(class = "kpi-icon kpi-icon-slate", icon("truck-medical")),
                                   tags$div(tags$div(class = "kpi-value", textOutput("kpi_emergency")),
                                            tags$div(class = "kpi-label", "With Emergency Care"))
                ))
              ),
              
              fluidRow(
                box(width = 7, title = "ICU Availability by State / Region — Top 15",
                    plotlyOutput("bar_icu", height = "360px")),
                box(width = 5, title = "Facility Type Breakdown",
                    plotlyOutput("bar_type", height = "360px"))
              ),
              fluidRow(
                box(width = 12, title = "Capability Coverage — All Facilities",
                    plotlyOutput("bar_capability", height = "250px"))
              )
      ),
      
      # ── MAP ───────────────────────────────────────────────────────────────────
      tabItem(tabName = "map",
              tags$div(class = "page-header-strip",
                       tags$div(
                         tags$h4("Facility Map"),
                         tags$p(textOutput("strip_location_map", inline = TRUE))
                       ),
                       tags$div(style = "display:flex; align-items:center; gap:16px; font-size:12px; color:#64748B;",
                                tags$span(tags$span(style="color:#0EA5E9; font-size:16px;", "●"), " ICU Available"),
                                tags$span(tags$span(style="color:#F43F5E; font-size:16px;", "●"), " No ICU")
                       )
              ),
              fluidRow(
                box(width = 12, leafletOutput("map_facilities", height = "660px"))
              )
      ),
      
      # ── CRISIS MAP ────────────────────────────────────────────────────────────
      tabItem(tabName = "crisis",
              tags$div(class = "page-header-strip",
                       tags$div(
                         tags$h4("Medical Desert Crisis Map"),
                         tags$p("PIN-code level risk scoring — darkest areas have the least healthcare coverage")
                       ),
                       tags$span(class = "page-tag", style = "background:#FFF1F2; color:#E11D48;",
                                 icon("fire"), " Highest-Risk Deserts")
              ),
              
              # Legend + KPI strip
              fluidRow(
                column(3, tags$div(class = "kpi-card kpi-border-coral",
                                   tags$div(class = "kpi-icon kpi-icon-coral", icon("triangle-exclamation")),
                                   tags$div(tags$div(class = "kpi-value", textOutput("crisis_desert_count")),
                                            tags$div(class = "kpi-label", "High-Risk PIN Codes"))
                )),
                column(3, tags$div(class = "kpi-card kpi-border-coral",
                                   tags$div(class = "kpi-icon kpi-icon-coral", icon("bed-pulse")),
                                   tags$div(tags$div(class = "kpi-value", textOutput("crisis_zero_icu")),
                                            tags$div(class = "kpi-label", "PIN Codes — Zero ICU"))
                )),
                column(3, tags$div(class = "kpi-card kpi-border-slate",
                                   tags$div(class = "kpi-icon kpi-icon-slate", icon("hospital")),
                                   tags$div(tags$div(class = "kpi-value", textOutput("crisis_pin_count")),
                                            tags$div(class = "kpi-label", "Total PIN Codes"))
                )),
                column(3, tags$div(class = "kpi-card kpi-border-slate",
                                   tags$div(class = "kpi-icon kpi-icon-slate", icon("map-pin")),
                                   tags$div(tags$div(class = "kpi-value", textOutput("crisis_avg_score")),
                                            tags$div(class = "kpi-label", "Avg Desert Score"))
                ))
              ),
              
              fluidRow(
                # Map
                column(8,
                       box(width = 12,
                           title = tags$span(
                             "Risk Intensity by PIN Code  ",
                             tags$span(style="font-size:11px; font-weight:400; color:#94A3B8;",
                                       "Circle size = facility count · Color = desert risk score")
                           ),
                           leafletOutput("crisis_map", height = "580px")
                       )
                ),
                # Top deserts table
                column(4,
                       box(width = 12, title = "Top 20 Medical Deserts",
                           tags$p(style="font-size:11px; color:#94A3B8; margin:0 0 10px;",
                                  "Ranked by desert score — lowest healthcare coverage"),
                           tags$div(style="overflow-x:auto; width:100%;", DTOutput("desert_table"))
                       )
                )
              ),
              
              # Color legend
              fluidRow(
                column(12,
                       tags$div(
                         style = "display:flex; align-items:center; gap:6px;
                       background:#fff; border:1px solid #E2E8F0;
                       border-radius:10px; padding:12px 20px;
                       font-size:12px; color:#64748B;",
                         tags$strong(style="margin-right:8px; color:#0F172A;", "Risk Scale:"),
                         tags$span(style="background:#10B981; width:14px; height:14px; border-radius:50%; display:inline-block;"),
                         tags$span("Low risk", style="margin-right:16px;"),
                         tags$span(style="background:#F59E0B; width:14px; height:14px; border-radius:50%; display:inline-block;"),
                         tags$span("Moderate risk", style="margin-right:16px;"),
                         tags$span(style="background:#F43F5E; width:14px; height:14px; border-radius:50%; display:inline-block;"),
                         tags$span("High risk", style="margin-right:16px;"),
                         tags$span(style="background:#7F1D1D; width:14px; height:14px; border-radius:50%; display:inline-block;"),
                         tags$span("Critical desert")
                       )
                )
              )
      ),
      
      # ── HIGH RISK ─────────────────────────────────────────────────────────────
      tabItem(tabName = "highrisk",
              tags$div(class = "page-header-strip",
                       tags$div(
                         tags$h4("High-Risk Facility Audit"),
                         tags$p("Facilities claiming surgery with no verified ICU or laboratory")
                       ),
                       tags$span(class = "page-tag", style = "background:#FFF1F2; color:#E11D48;",
                                 icon("triangle-exclamation"), " Data Integrity Flag")
              ),
              tags$div(class = "alert-coral",
                       tags$strong("483 facilities"), " report surgical services but lack corroborating ICU and laboratory infrastructure — the primary contradiction signal in this dataset."
              ),
              fluidRow(
                box(width = 12,
                    title = "Surgery Claimed · ICU & Lab Missing",
                    DTOutput("table_highrisk"))
              )
      ),
      
      # ── SPECIALTIES ───────────────────────────────────────────────────────────
      tabItem(tabName = "specialty",
              tags$div(class = "page-header-strip",
                       tags$div(
                         tags$h4("Specialty & Operator Analysis"),
                         tags$p("Distribution of medical specialties and operator types across India")
                       ),
                       tags$span(class = "page-tag", "All Facilities")
              ),
              fluidRow(
                box(width = 8, title = "Top 15 Specialties",
                    plotlyOutput("bar_specialty", height = "380px")),
                box(width = 4, title = "Operator Type Distribution",
                    plotlyOutput("pie_operator", height = "380px"))
              ),
              
              tags$div(
                style = "background:#F0F9FF; border:1px solid #BAE6FD; border-left:3px solid #0EA5E9; border-radius:10px; padding:14px 20px; margin:4px 0 16px;",
                tags$p(style="margin:0; font-size:13px; color:#0C4A6E;",
                       icon("flask"), "  ",
                       tags$strong("Research Area — Confidence Scoring:"),
                       " VeriCare computes a four-signal confidence score per facility — completeness, recency, internal consistency, and social proof — and uses Wilson score intervals adjusted by data confidence to bound every aggregate claim statistically."
                )
              ),
              fluidRow(
                box(width = 6,
                    title = "Data Confidence Distribution",
                    tags$p(style="font-size:11px;color:#94A3B8;margin:0 0 8px;", "How reliable is the data behind each facility record?"),
                    plotlyOutput("bar_confidence", height = "260px")),
                box(width = 6,
                    title = "Average Data Confidence by State / Region",
                    tags$p(style="font-size:11px;color:#94A3B8;margin:0 0 8px;", "Lower scores = wider prediction intervals on all claims"),
                    plotlyOutput("bar_conf_state", height = "260px"))
              )
      )
    )
  )
)