# EPA GHGRP Direct Point Emitters: Emissions Trends, 2010-2023 ----

# Question: How did reported direct emissions change from 2010 to 2023, and how much of that change holds up when we only look at facilities reported in every year?

# Data: EPA Greenhouse Gas Reporting Program (GHGRP), yearly data summary spreadsheets. Download the zip from EPA's GHGRP data page and put the files named ghgp_data_YYYY.xlsx in data/raw/ (see README).
# Run from the project root (open the folder as an RStudio Project).
# Packages: tidyverse, readxl, janitor

# Note: GHGRP covers large direct emitters only, NOT total U.S. emissions.
# Last run: October 2026

# 1. Setup ----
# install.packages(c("tidyverse", "readxl", "janitor"))
library(tidyverse)
library(readxl)
library(janitor)

# Study period doesn't depend on files in folder, but our choice
study_start <- 2010
study_end <- 2023
study_years <- study_start:study_end

# Where the downloaded EPA spreadsheets go
data_dir <- "data/raw" 

# Where plots are saved (created if it doesn't exist)
output_dir <- "figures"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# 2. Find yearly files ----
# Pattern = starts with "ghgp_data_", 4-digit year, ".xlsx"
# (skips Excel's temporary ~$ lock files and the ""by_year" summary file)
files <- list.files(data_dir,
                    pattern = "^ghgp_data_[0-9]{4}\\.xlsx$",
                    full.names = TRUE)

#Keep only files inside study period
file_years <- parse_number(basename(files))
files <- files[file_years >= study_start & file_years <= study_end]

stopifnot("No files found. Check data_dir and the file names." = length(files) > 0)

# 3. Import and combine every year ----
# sheet = 1: Direct Point Emitters data is on the first tab
# skip = 3: first 3 rows are group labels above the real column names
# guess_max = 100000: Scans many rows when detecting column types, as default is 1,000 rows
# clean_names(): Standardizes headers so columns are easy to reference
# year: taken from the filename (e.g. "ghgp_data_2022.xlsx" -> 2022)
read_ghgp_year <- function(path) {
  read_excel(path, sheet = 1, skip = 3, guess_max = 100000) |>
    clean_names() |>
    mutate(year = parse_number(basename(path)))
}  

# Apply the function to every file and stack results into one table
ghgp_multi <- map_dfr(files, read_ghgp_year)

# Data Checks: Stop early if the data isn't shaped the way analysis assumes
required_cols <- c("facility_id", "industry_type_sectors",
                   "total_reported_direct_emissions", "year")
stopifnot("A required column is missing (names may differ across years)." =
            all(required_cols %in% names(ghgp_multi)))

stopifnot("Years in the data don't match the study period." =
            setequal(ghgp_multi$year, study_years))

stopifnot("Some rows have no facility_id." = !anyNA(ghgp_multi$facility_id))

stopifnot("Emissions were not read as numbers; check the source files." = 
            is.numeric(ghgp_multi$total_reported_direct_emissions))

# Each facility should appear at most once per year
duplicates <- ghgp_multi |>
  count(facility_id, year) |>
  filter(n>1)
stopifnot("Duplicate facility-year rows found; investigate before continuing." =
            nrow(duplicates) == 0)

# Missing emissions values are skipped by na.rm = TRUE below, so check how many there are
ghgp_multi |>
  group_by(year) |>
  summarise(n_rows = n(),
            n_missing_emissions = sum(is.na(total_reported_direct_emissions)),
            .groups = "drop") |>
  print(n = Inf)

# 4. Group sectors ----
# industry_type_sectors lists every sector a facility is registered under, comma-separated
# str_detect(): TRUE if cell contains a comma, meaning more than one sector
# if_else(): label those facilities "Multiple sectors", keeps single-sector names as is
# Limitation: ~15% of emissions fall in "Multiple sectors", and most refineries are registered in combinations, so refineries are understated
ghgp_multi <- ghgp_multi |>
  mutate(sector = if_else(str_detect(industry_type_sectors, ","),
                          "Multiple sectors",
                          industry_type_sectors))

# Share of total emissions by sector (pooled across all years)
ghgp_multi |>
  group_by(sector) |>
  summarise(total_billions = sum(total_reported_direct_emissions, na.rm = TRUE)/1e9,
            n = n()) |>
  mutate(share = total_billions / sum(total_billions)) |>
  arrange(desc(total_billions)) |>
  print(n = Inf)

# 5. Create Balanced Set (Facilities reported in every year) ----
# Why: Because number of reporting facilities changes over time, a falling total could just mean fewer facilities reporting
# group_by(facility_id): checks each facility separately
# n_distinct(year): number of years that facility appears in
# filter(): Keep facilities present throughout all years
# ungroup(): removes grouping so later steps work throughout whole table
ghgp_balanced <- ghgp_multi |>
  group_by(facility_id) |>
  filter(n_distinct(year) == n_distinct(ghgp_multi$year)) |>
  ungroup()

# Number of facilities reported every year
n_balanced <- n_distinct(ghgp_balanced$facility_id)

message("Facilities that reported in every year: ", n_balanced)

#Check: Do facilities keep the same sector label across years?
# (2010-2023: 4,261 keep one label; 429, about 9%, change at least once)
ghgp_balanced |>
  group_by(facility_id) |>
  summarise(n_sectors = n_distinct(sector)) |>
  count(n_sectors)

# Fix each facility's sector to its label in the first year
# Why: 9% of balanced facilities change sector label over time, which moves their emissions between categories even if nothing about the facility changed
# filter(year == study_start): keep each facility's first-year row
# select(facility_id, sector_fixed = sector): keeps just the ID and first-year label
# left_join(): attach that fixed label to every row of the same facility
n_rows_before <- nrow(ghgp_balanced)

first_sector <- ghgp_balanced |>
  filter(year == min(year)) |>
  select(facility_id, sector_fixed = sector)

ghgp_balanced_fixed <- ghgp_balanced |>
  left_join(first_sector, by = "facility_id")

# stopifnot(): stops with an error if the join changed the row count
stopifnot("The sector-label join changed the number of rows." =
  nrow(ghgp_balanced_fixed) == n_rows_before)

# 6. Yearly totals (All facilities v.s. Balanced Set) ----
# mutate(dataset = ..."): labels each table so rows can be distinguished when stacked
# bind_rows(): stacks labeled tables into one table
# group_by(dataset, year): one group per dataset per year
# total_billions: sum of emissions/1e9, in billions of metric tons CO2e
# na.rm = TRUE: ignore missing values so one NA doesn't turn total into NA
# n_facilities: facilities per year, to show whether the total change with number of reporters
# .groups = "drop": removes grouping after summarising
yearly_comparison <- bind_rows(
  ghgp_multi    |> mutate(dataset = "All facilities"),
  ghgp_balanced |> mutate(dataset = "Reported every year")
) |>
  group_by(dataset, year) |>
  summarise(total_billions = sum(total_reported_direct_emissions, na.rm = TRUE) / 1e9,
            n_facilities = n_distinct(facility_id),
            .groups = "drop")

# print(n = Inf) shows every row (tibbles only shows 10 by default)           
print(yearly_comparison, n = Inf)

# Percent change from first to last year calculated from the data (used in plot subtitle so never goes stale)
trend_summary <- yearly_comparison |>
  group_by(dataset) |>
  summarise(start = total_billions[year == study_start],
            end   = total_billions[year == study_end],
            pct_change = (end-start)/start*100,
            .groups = "drop")

print(trend_summary)

# Declines as positive numbers, for the subtitle
decline_range <- range(-trend_summary$pct_change)

# 7. Plot total emissions over time ----
# x = year; color = dataset: one line per dataset
# scale_x_continuous(breaks = ...): labels every year
# y_max: highest value rounded up to next 0.5, so the axis fits the data
# scale_y_continuous():
#   limits = c(0, y_max): starts axis at zero so decline isn't visually exaggerated;
#   breaks = seq(0, y_max, by = 0.5): tick marks every 0.5 billion tons
#   labels = scales::label_number(accuracy = 0.1): shows one decimal place on every tick
#     (otherwise whole numbers print as "1", "2", "3")
# theme(axis.text.x = ...): tilt year labels so they don't overlap
# theme(plot.caption...): aligns caption to the left edge so it isn't cut off
y_max <- ceiling(max(yearly_comparison$total_billions) *2) / 2

emissions_plot <- ggplot(yearly_comparison, 
                         aes(x = year, y = total_billions, color = dataset)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  scale_x_continuous(breaks = study_start:study_end) +
  scale_y_continuous(limits = c(0, 3.5),
                     breaks = seq(0, 3.5, by = 0.5),
                     labels = scales::label_number(accuracy = 0.1)) +
  labs(title = paste0("Total Reported Direct Emissions, ", study_start, "-", study_end),
       subtitle = sprintf("Emissions fell about %.1f-%.1f%%, whether or not facility turnover is accounted for",
                          decline_range[1], decline_range[2]),
       x = NULL, 
       y = "Billion metric tons CO2e", 
       color = NULL,
       caption = "Source: EPA Greenhouse Gas Reporting Program. Large direct emitters only, not total U.S. emissions.") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        plot.caption.position = "plot",
        plot.caption = element_text(hjust = 0))

emissions_plot

# Save the plot as an image (width/height in inches; dpi = sharpness)
ggsave(file.path(output_dir, paste0("emissions_trend_", study_start, "_", study_end, ".png")),
       plot = emissions_plot, width = 9, height = 5, dpi = 300)

# 8. Emissions by sector ----
# Yearly emissions by sector (using the balanced set, fixed first-year sector labels)
# Why balanced: same facilities every year, so a sector's trend isn't driven by facilities entering or leaving program
sector_totals_fixed <- ghgp_balanced_fixed |>
  group_by(sector_fixed, year) |>
  summarise(total_billions = sum(total_reported_direct_emissions, na.rm = TRUE)/1e9,
            .groups = "drop")

# Change from first to last year. Percent change is undefined if sector started at zero, so those are set to NA.
# abs_change: change in billions of tons
# pct_change: change relative to the sta
sector_change_fixed <- sector_totals_fixed |>
  group_by(sector_fixed) |>
  summarise(start = total_billions[year == study_start],
            end   = total_billions[year == study_end],
            .groups = "drop") |>
  mutate(abs_change = end-start,
         pct_change = if_else(start == 0, NA_real_, abs_change/start*100))

# Look at the numbers before interpreting plot
print(sector_change_fixed, n = Inf)

# 9. Plot change in emissions by sector ----
# One function builds both sector plots so the style remains identical
# Absolute change, so small sectors with large percent changes don't look as important as large sectors
# reorder(): sort bars by size of change
# coord_flip(): horizontal bars for readable names
# geom_text(): value labels
plot_sector_change <- function(data, title, subtitle = NULL, caption) {
  ggplot(data, aes(x = reorder(sector_fixed, abs_change), y = abs_change)) +
    geom_col(fill = "steelblue") +
    geom_hline(yintercept = 0) +
    geom_text(aes(label = round(abs_change, 3),
                  hjust = if_else(abs_change <0, 1.1, -0.1)),
              size = 3.5) +
    scale_y_continuous(expand = expansion(mult = c(0.12, 0.12))) +
    coord_flip() + 
    labs(title = title, subtitle = subtitle, x = NULL,
         y = "Change (billion metric tons CO2e)", caption = caption) +
    theme_minimal() +
    theme(plot.caption.position = "plot",
          plot.caption = element_text(hjust = 0))
}

sector_caption <- paste0("Facilities reporting in every year, each assigned its ", study_start,
                         " sector label.\n",
                         "Facilities registered under more than one sector are grouped as 'Multiple sectors'.\n",
                         "Source: EPA Greenhouse Gas Reporting Program")

sector_plot <- plot_sector_change(
  sector_change_fixed,
  title = paste0("Change in Emissions by Sector, ", study_start, " to ", study_end),
  caption = sector_caption
)

sector_plot

ggsave(file.path(output_dir, "sector_change.png"),
       plot = sector_plot, width = 9, height = 5, dpi = 300)

# Same plot without Power Plants, so the smaller changes are visible
# Note: the axis here is much smaller than in the main plot, so don't compare bar lengths across the two
sector_no_power <- sector_change_fixed |>
  filter(sector_fixed != "Power Plants")

largest_change <- max(abs(sector_no_power$abs_change))

sector_no_power_plot <- plot_sector_change(
  sector_no_power,
  title = "Change in Emissions by Sector, Excluding Power Plants",
  subtitle = sprintf("Note the smaller scale: the largest change here is %.3f billion tons",
                     largest_change),
  caption = sector_caption
)

sector_no_power_plot
ggsave(file.path(output_dir, "sector_change_no_power.png"),
       plot = sector_no_power_plot, width = 9, height = 5)