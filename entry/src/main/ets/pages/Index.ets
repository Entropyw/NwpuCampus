import web_webview from '@ohos.web.webview';
import common from '@ohos.app.ability.common';

interface POI {
  name: string;
  lat: number;
  lon: number;
}

interface Marker {
  lat: number;
  lon: number;
  label?: string;
}

interface RoutePayload {
  start: Marker;
  end: Marker;
}

interface SelectOption {
  value: string;
  text: string;
}

@Entry
@Component
struct Index {
  private webController: web_webview.WebviewController = new web_webview.WebviewController();
  private osmInjected: boolean = false;
  private startIndex: number = 0;
  private endIndex: number = 1;

  private poiList: Array<POI> = [
    { name: '东门', lat: 34.03204, lon: 108.76465 },
    { name: '西门', lat: 34.02023, lon: 108.75439 },
    { name: '南门', lat: 34.02519, lon: 108.76427 },
    { name: '北门', lat: 34.03922, lon: 108.75466 },
    { name: '图书馆', lat: 34.03169, lon: 108.76358 },
    { name: '一号教学楼', lat: 34.02969, lon: 108.76369 },
    { name: '宿舍区', lat: 34.02925, lon: 108.76286 },
    { name: '体育场', lat: 34.03299, lon: 108.75783 }
  ];

  private async injectOsmToWeb(): Promise<void> {
    if (this.osmInjected) {
      return;
    }
    try {
      // read raw file content; resourceManager.getRawFileContent may return ArrayBuffer, Uint8Array or string
      const buffer: ArrayBuffer | Uint8Array | string = await getContext(this).resourceManager.getRawFileContent('map.osm');
      let osmText: string = '';
      if (typeof buffer === 'string') {
        osmText = buffer;
      } else if (buffer instanceof ArrayBuffer) {
        osmText = this.utf8ArrayToStr(new Uint8Array(buffer));
      } else if (buffer instanceof Uint8Array) {
        osmText = this.utf8ArrayToStr(buffer as Uint8Array);
      } else if (Array.isArray(buffer)) {
        osmText = this.utf8ArrayToStr(new Uint8Array(buffer as number[]));
      } else {
        osmText = String(buffer);
      }
      const script = `window.setOSMText && window.setOSMText(${JSON.stringify(osmText)});`;
      this.webController.runJavaScript(script);
      this.osmInjected = true;
      this.updateMarkers();
    } catch (error) {
      console.error(`OSM 注入失败: ${String(error)}`);
    }
  }


  // UTF-8 decoder for ArrayBuffer/Uint8Array -> string (avoids depending on TextDecoder/util)
  private utf8ArrayToStr(bytes: Uint8Array): string {
    let out = '';
    let i = 0;
    while (i < bytes.length) {
      const c = bytes[i++];
      if (c < 0x80) {
        out += String.fromCharCode(c);
      } else if (c >= 0xc0 && c < 0xe0) {
        const c2 = bytes[i++];
        out += String.fromCharCode(((c & 0x1f) << 6) | (c2 & 0x3f));
      } else if (c >= 0xe0 && c < 0xf0) {
        const c2 = bytes[i++];
        const c3 = bytes[i++];
        out += String.fromCharCode(((c & 0x0f) << 12) | ((c2 & 0x3f) << 6) | (c3 & 0x3f));
      } else {
        // 4-byte UTF-8 -> surrogate pair
        const c2 = bytes[i++];
        const c3 = bytes[i++];
        const c4 = bytes[i++];
        let codepoint = ((c & 0x07) << 18) | ((c2 & 0x3f) << 12) | ((c3 & 0x3f) << 6) | (c4 & 0x3f);
        codepoint -= 0x10000;
        out += String.fromCharCode((codepoint >> 10) + 0xd800);
        out += String.fromCharCode((codepoint & 0x3ff) + 0xdc00);
      }
    }
    return out;
  }

  private cycleStart(): void {
    const combined = this.getCombinedList();
    this.startIndex = (this.startIndex + 1) % combined.length;
    if (this.startIndex === this.endIndex) {
      this.endIndex = (this.endIndex + 1) % combined.length;
    }
    this.updateMarkers();
  }

  private cycleEnd(): void {
    const combined = this.getCombinedList();
    this.endIndex = (this.endIndex + 1) % combined.length;
    if (this.endIndex === this.startIndex) {
      this.startIndex = (this.startIndex + 1) % combined.length;
    }
    this.updateMarkers();
  }

  private swapPoints(): void {
    const tmp = this.startIndex;
    this.startIndex = this.endIndex;
    this.endIndex = tmp;
    this.updateMarkers();
  }

  private getSelectOptions(): Array<SelectOption> {
    const filtered: Array<POI> = this.getFilteredList();
    const options: Array<SelectOption> = new Array<SelectOption>();
    for (let i = 0; i < filtered.length; i++) {
      const poi: POI = filtered[i];
      const opt: SelectOption = { value: poi.name, text: poi.name };
      options.push(opt);
    }
    return options;
  }

  private getFilteredList(): Array<POI> {
    // Host no longer filters POIs; selection/search is handled in the webview.
    return this.getCombinedList();
  }

  private getCombinedList(): Array<POI> {
    // For host-side operations we only keep the built-in POI list.
    return this.poiList.slice();
  }

  private updateMarkers(): void {
    const combined = this.getCombinedList();
    const start: POI = combined[this.startIndex] || this.poiList[0];
    const end: POI = combined[this.endIndex] || this.poiList[1] || combined[0];
    const markers: Array<Marker> = new Array<Marker>();
    const startMarker: Marker = { lat: start.lat, lon: start.lon, label: '起点 ' + start.name };
    const endMarker: Marker = { lat: end.lat, lon: end.lon, label: '终点 ' + end.name };
    markers.push(startMarker);
    markers.push(endMarker);
    const script = `window.setCustomMarkers && window.setCustomMarkers(${JSON.stringify(markers)});`;
    this.webController.runJavaScript(script);
  }

  private planRoute(): void {
    const combined = this.getCombinedList();
    const start: POI = combined[this.startIndex] || this.poiList[0];
    const end: POI = combined[this.endIndex] || this.poiList[1] || combined[0];
    const startPayload: Marker = { lat: start.lat, lon: start.lon };
    const endPayload: Marker = { lat: end.lat, lon: end.lon };
    const payload: RoutePayload = { start: startPayload, end: endPayload };
    const script = `window.setRoute && window.setRoute(${JSON.stringify(payload)});`;
    this.webController.runJavaScript(script);
  }

  private computeSelectedIndexForStart(): number {
    const filtered: Array<POI> = this.getFilteredList();
    const combined: Array<POI> = this.getCombinedList();
    const current: POI | undefined = combined[this.startIndex];
    if (!current) {
      return 0;
    }
    for (let i = 0; i < filtered.length; i++) {
      const p: POI = filtered[i];
      if (p.name === current.name && p.lat === current.lat && p.lon === current.lon) {
        return i;
      }
    }
    return 0;
  }

  private computeSelectedIndexForEnd(): number {
    const filtered: Array<POI> = this.getFilteredList();
    const combined: Array<POI> = this.getCombinedList();
    const current: POI | undefined = combined[this.endIndex];
    if (!current) {
      return 0;
    }
    for (let i = 0; i < filtered.length; i++) {
      const p: POI = filtered[i];
      if (p.name === current.name && p.lat === current.lat && p.lon === current.lon) {
        return i;
      }
    }
    return 0;
  }

  private clearRoute(): void {
    const script = 'window.clearRoute && window.clearRoute();';
    this.webController.runJavaScript(script);
  }

  // onPageEnd handler must be a named method (avoid nested inline functions)
  private onWebPageEnd(): void {
    this.injectOsmToWeb();
  }

  build() {
    // Single root stack containing the Web component. Keep chaining on the root.
    Stack() {
      Web({
        src: 'resource://rawfile/custom_map.html',
        controller: this.webController
      })
        .onPageEnd(this.onWebPageEnd.bind(this))
        .width('100%')
        .height('100%');
    }
    .width('100%')
    .height('100%');
  }
}