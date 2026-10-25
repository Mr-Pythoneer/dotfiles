pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Weather from Open-Meteo for wherever the network says you are (like Caelestia's), refreshed every 30 minutes
Singleton {
    id: root

    property string city: ""
    property real lat: NaN
    property real lon: NaN
    property bool ready: false
    property real temp: 0
    property real feels: 0
    property int code: 0
    property bool isDay: true
    property int humidity: 0
    property real wind: 0
    property var hourly: []     // [{time, temp, code, rain}]
    property var daily: []      // [{date, max, min, code, rain}]

    function describe(c: int): string {
        if (c === 0) return "Clear";
        if (c <= 2) return "Partly cloudy";
        if (c === 3) return "Overcast";
        if (c <= 48) return "Fog";
        if (c <= 57) return "Drizzle";
        if (c <= 67) return "Rain";
        if (c <= 77) return "Snow";
        if (c <= 82) return "Showers";
        if (c <= 86) return "Snow showers";
        return "Thunderstorm";
    }

    function icon(c: int, day: bool): string {
        if (c === 0) return day ? "clear_day" : "clear_night";
        if (c <= 2) return day ? "partly_cloudy_day" : "partly_cloudy_night";
        if (c === 3) return "cloud";
        if (c <= 48) return "foggy";
        if (c <= 67 || (c >= 80 && c <= 82)) return "rainy";
        if (c <= 77 || c <= 86) return "weather_snowy";
        return "thunderstorm";
    }

    // the icon's colour: sun amber, night blue, cloud and fog grey, rain blue, snow white, storms mauve
    function tint(c: int, day: bool): color {
        if (c <= 2) return day ? Theme.amber : Theme.blue;
        if (c <= 48) return Theme.fgDim;
        if (c <= 67 || (c >= 80 && c <= 82)) return Theme.blue;
        if (c <= 86) return Theme.fg;
        return Theme.mauve;
    }

    function get(url: string, done: var): void {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status === 200) {
                try {
                    done(JSON.parse(xhr.responseText));
                } catch (e) {}
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function locate(): void {
        get("http://ip-api.com/json?fields=status,city,lat,lon", d => {
            if (d.status !== "success")
                return;
            root.city = d.city;
            root.lat = d.lat;
            root.lon = d.lon;
            fetch();
        });
    }

    function fetch(): void {
        if (isNaN(root.lat))
            return locate();
        const url = `https://api.open-meteo.com/v1/forecast?latitude=${root.lat}&longitude=${root.lon}&current=temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m&hourly=temperature_2m,weather_code,precipitation_probability&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=7`;
        get(url, d => {
            const c = d.current;
            root.temp = c.temperature_2m;
            root.feels = c.apparent_temperature;
            root.code = c.weather_code;
            root.isDay = c.is_day === 1;
            root.humidity = c.relative_humidity_2m;
            root.wind = c.wind_speed_10m;
            const now = Date.now();
            const hrs = [];
            for (let i = 0; i < d.hourly.time.length && hrs.length < 12; i++) {
                const t = new Date(d.hourly.time[i]);
                if (t.getTime() + 3600000 < now)
                    continue;
                hrs.push({ time: t, temp: d.hourly.temperature_2m[i], code: d.hourly.weather_code[i], rain: d.hourly.precipitation_probability[i] });
            }
            root.hourly = hrs;
            root.daily = d.daily.time.map((t, i) => ({ date: new Date(t + "T12:00"), max: d.daily.temperature_2m_max[i], min: d.daily.temperature_2m_min[i], code: d.daily.weather_code[i], rain: d.daily.precipitation_probability_max[i] }));
            root.ready = true;
        });
    }

    Timer {
        interval: 30 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetch()
    }
}
