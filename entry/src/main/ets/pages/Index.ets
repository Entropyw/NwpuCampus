import web_webview from '@ohos.web.webview';
import util from '@ohos.util';

@Entry
@Component
struct Index {
  private webController: web_webview.WebviewController = new web_webview.WebviewController();
  private osmInjected: boolean = false;

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
    } catch (error) {
      this.osmInjected = false;
    }
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
    }
    .width('100%')
    .height('100%');
  }
}