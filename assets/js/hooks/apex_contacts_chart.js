import ApexCharts from "apexcharts"
import { buildTooltip } from "flyonui/src/js/helpers/apexcharts/index.ts"

const parseJson = (value, fallback) => {
  try {
    return JSON.parse(value || "")
  } catch (_) {
    return fallback
  }
}

const ApexContactsChart = {
  mounted() {
    this._render()
  },

  destroyed() {
    this._destroy()
  },

  _render() {
    const labels = parseJson(this.el.dataset.labels, [])
    const values = parseJson(this.el.dataset.values, [])

    this._chart = new ApexCharts(this.el, {
      chart: {
        height: 280,
        type: "bar",
        parentHeightOffset: 0,
        toolbar: { show: false },
        animations: {
          enabled: true,
          easing: "easeinout",
          speed: 450,
        },
      },
      series: [
        {
          name: this.el.dataset.seriesName || "Contacts",
          data: values,
        },
      ],
      colors: ["var(--color-primary)"],
      dataLabels: { enabled: false },
      grid: {
        strokeDashArray: 3,
        borderColor: "color-mix(in oklab, var(--color-base-content) 16%, transparent)",
      },
      plotOptions: {
        bar: {
          borderRadius: 7,
          columnWidth: "44%",
          distributed: true,
        },
      },
      legend: { show: false },
      xaxis: {
        categories: labels,
        axisBorder: { show: false },
        axisTicks: { show: false },
        labels: {
          style: {
            colors: "var(--color-base-content)",
            fontSize: "12px",
            fontWeight: 500,
          },
        },
      },
      yaxis: {
        min: 0,
        labels: {
          style: {
            colors: "var(--color-base-content)",
            fontSize: "12px",
          },
          formatter: value => Math.round(value),
        },
      },
      tooltip: {
        custom: props => buildTooltip(props, {
          title: labels[props.dataPointIndex],
          valuePrefix: "",
          valuePostfix: "",
          hasTextLabel: true,
          markerExtClasses: "bg-primary",
        }),
      },
      responsive: [
        {
          breakpoint: 640,
          options: {
            chart: { height: 240 },
            plotOptions: {
              bar: {
                columnWidth: "58%",
              },
            },
          },
        },
      ],
    })

    this._chart.render()
  },

  _destroy() {
    if (this._chart) {
      this._chart.destroy()
      this._chart = null
    }
  },
}

export default ApexContactsChart
