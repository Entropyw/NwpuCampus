import web_webview from '@ohos.web.webview';
import util from '@ohos.util';

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

  private readonly poiList: Array<POI> = [
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
      const context = getContext(this);
      const buffer = await context.resourceManager.getRawFileContent('map.osm');
      const decoder = new util.TextDecoder('utf-8');
      const osmText = decoder.decode(buffer);
      const script = `window.setOSMText && window.setOSMText(${JSON.stringify(osmText)});`;
      this.webController.runJavaScript(script);
      this.osmInjected = true;
      this.updateMarkers();
    } catch (error) {
      this.osmInjected = false;
    }
  }

  private cycleStart(): void {
    this.startIndex = (this.startIndex + 1) % this.poiList.length;
    if (this.startIndex === this.endIndex) {
      this.endIndex = (this.endIndex + 1) % this.poiList.length;
    }
    this.updateMarkers();
  }

  private cycleEnd(): void {
    this.endIndex = (this.endIndex + 1) % this.poiList.length;
    if (this.endIndex === this.startIndex) {
      this.startIndex = (this.startIndex + 1) % this.poiList.length;
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
    const options: Array<SelectOption> = new Array<SelectOption>();
    for (let i = 0; i < this.poiList.length; i++) {
      const poi: POI = this.poiList[i];
      const opt: SelectOption = { value: poi.name, text: poi.name };
      options.push(opt);
    }
    return options;
  }

  private updateMarkers(): void {
    const start: POI = this.poiList[this.startIndex];
    const end: POI = this.poiList[this.endIndex];
    const markers: Array<Marker> = new Array<Marker>();
    const startMarker: Marker = { lat: start.lat, lon: start.lon, label: '起点 ' + start.name };
    const endMarker: Marker = { lat: end.lat, lon: end.lon, label: '终点 ' + end.name };
    markers.push(startMarker);
    markers.push(endMarker);
    const script = `window.setCustomMarkers && window.setCustomMarkers(${JSON.stringify(markers)});`;
    this.webController.runJavaScript(script);
  }

  private planRoute(): void {
    const start: POI = this.poiList[this.startIndex];
    const end: POI = this.poiList[this.endIndex];
    const startPayload: Marker = { lat: start.lat, lon: start.lon };
    const endPayload: Marker = { lat: end.lat, lon: end.lon };
    const payload: RoutePayload = { start: startPayload, end: endPayload };
    const script = `window.setRoute && window.setRoute(${JSON.stringify(payload)});`;
    this.webController.runJavaScript(script);
  }

  private clearRoute(): void {
    const script = 'window.clearRoute && window.clearRoute();';
    this.webController.runJavaScript(script);
  }

  build() {
    Stack() {
      Web({
        src: 'resource://rawfile/custom_map.html',
        controller: this.webController
      })
        .onPageEnd(() => {
          this.injectOsmToWeb();
        })
        .width('100%')
        .height('100%');

      Row() {
        Text('本地 OSM 地图 · 支持双指缩放与拖动')
          .fontSize(14)
          .fontColor(Color.White)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('rgba(0, 0, 0, 0.55)')
          .borderRadius(16);
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 18 });

      Column() {
        Row() {
          Text('起点').fontColor(Color.White).fontSize(13).opacity(0.85);
          Select(this.getSelectOptions())
            .selected(this.startIndex)
            .margin({ left: 8 })
            .onSelect((index: number) => {
              if (index >= 0 && index < this.poiList.length) {
                this.startIndex = index;
                if (this.startIndex === this.endIndex) {
                  this.endIndex = (this.endIndex + 1) % this.poiList.length;
                }
                this.updateMarkers();
              }
            });
        }
        .width('100%')
        .padding({ bottom: 8 });

        Row() {
          Text('终点').fontColor(Color.White).fontSize(13).opacity(0.85);
          Select(this.getSelectOptions())
            .selected(this.endIndex)
            .margin({ left: 8 })
            .onSelect((index: number) => {
              if (index >= 0 && index < this.poiList.length) {
                this.endIndex = index;
                if (this.endIndex === this.startIndex) {
                  this.startIndex = (this.startIndex + 1) % this.poiList.length;
                }
                this.updateMarkers();
              }
            });
        }
        .width('100%')
        .padding({ bottom: 12 });

        Row() {
          Button('规划路线').fontSize(12).onClick(() => this.planRoute());
          Button('清除').fontSize(12).margin({ left: 8 }).onClick(() => this.clearRoute());
        }
      }
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor('rgba(0, 0, 0, 0.45)')
      .borderRadius(12)
      .width('92%')
      .margin({ top: 70 })
      .align(Alignment.TopStart);
    }
    .width('100%')
    .height('100%');
  }
}