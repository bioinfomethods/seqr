/**
 * @jest-environment jsdom
 */
import React from 'react'
import { shallow, mount, configure } from 'enzyme'
import Adapter from '@wojtekmaj/enzyme-adapter-react-17'
import configureStore from 'redux-mock-store'
import Frequencies from './Frequencies'
import { VARIANT, SV_VARIANT, STATE1 } from '../fixtures'

configure({ adapter: new Adapter() })

test('shallow-render without crashing', () => {
  const store = configureStore()(STATE1)
  shallow(<Frequencies store={store} variant={VARIANT} />)
  shallow(<Frequencies store={store} variant={SV_VARIANT} />)
})

// Per-assay observation counts are subfields of a single population: populations.seqr
// carries ac_wes / ac_wgs / ac_lrs alongside the combined ac. Each assay row must read
// its own suffix, and rows with no data for an assay must not render.
// STATE1 omits totalSampleCounts; production supplies it via the RECEIVE_DATA reducer,
// and the component calls Object.keys() on it unguarded.
const assayState = { ...STATE1, totalSampleCounts: { SNV_INDEL: { WES: 100, WGS: 50 } } }

const assayVariant = {
  ...VARIANT,
  populations: {
    ...VARIANT.populations,
    seqr: { ac: 12, hom: 1, ac_wes: 7, hom_wes: 0, ac_wgs: 5, hom_wgs: 1 },
  },
}

test('renders a row per assay with that assay\'s counts', () => {
  const store = configureStore()(assayState)
  const text = mount(<Frequencies store={store} variant={assayVariant} />).text()

  expect(text).toContain('MCRI exomes')
  expect(text).toContain('AC=7')
  expect(text).toContain('MCRI genomes')
  expect(text).toContain('AC=5')
  // the combined seqr row still shows the total, unchanged by this feature
  expect(text).toContain('AC=12')
})

test('omits an assay row when that assay has no count', () => {
  const store = configureStore()(assayState)
  const text = mount(<Frequencies store={store} variant={assayVariant} />).text()

  // ac_lrs is absent from the fixture, so the long-read row must not render at all
  // rather than showing a misleading zero
  expect(text).not.toContain('MCRI long read')
})
