import { describe, it, expect } from '@ohos/hypium';
import { OsmParser } from '../main/ets/services/OsmParser';

export default function osmParserTest() {
  describe('OsmParser', () => {
    it('parses minimal osm', 0, () => {
      const osmText = `<?xml version="1.0"?>
<osm>
  <bounds minlat="34.0" minlon="108.0" maxlat="34.1" maxlon="108.1" />
  <node id="1" lat="34.01" lon="108.01"><tag k="name" v="A"/></node>
  <node id="2" lat="34.02" lon="108.02" />
  <way id="10">
    <nd ref="1"/>
    <nd ref="2"/>
    <tag k="highway" v="footway"/>
    <tag k="name" v="Road"/>
  </way>
</osm>`;
      const parser = new OsmParser();
      const data = parser.parse(osmText);
      expect(data.labels.length).assertEqual(2);
      expect(data.roads.length).assertEqual(1);
      expect(data.bounds.minLat).assertEqual(34.0);
    });
  });
}
