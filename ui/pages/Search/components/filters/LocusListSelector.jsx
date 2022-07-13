import PropTypes from 'prop-types'
import React from 'react'
import { connect } from 'react-redux'
import { FormSpy } from 'react-final-form'
import { Dropdown, Multiselect } from 'shared/components/form/Inputs'
import { LocusListItemsLoader } from 'shared/components/LocusListLoader'
import { PANEL_APP_MOI_OPTIONS } from 'shared/utils/constants'
import { moiToMoiInitials, panelAppLocusListReducer } from 'shared/utils/panelAppUtils'
import { getSearchedProjectsLocusListOptions } from '../../selectors'

class BaseLocusListDropdown extends React.Component {

  static propTypes = {
    locusList: PropTypes.object,
    projectLocusListOptions: PropTypes.arrayOf(PropTypes.object),
    onChange: PropTypes.func,
    selectedMOIs: PropTypes.arrayOf(PropTypes.string),
  }

  shouldComponentUpdate(nextProps) {
    const { locusList, selectedMOIs, projectLocusListOptions, onChange } = this.props

    return nextProps.projectLocusListOptions !== projectLocusListOptions ||
      nextProps.selectedMOIs !== selectedMOIs ||
      nextProps.onChange !== onChange ||
      nextProps.locusList.locusListGuid !== locusList.locusListGuid ||
      (!!locusList.locusListGuid && nextProps.locusList.rawItems !== locusList.rawItems)
  }

  componentDidUpdate(prevProps) {
    const { locusList, onChange, selectedMOIs } = this.props
    if (prevProps.locusList.rawItems !== locusList.rawItems || prevProps.selectedMOIs !== selectedMOIs) {
      const { locusListGuid } = locusList

      if (locusList.paLocusList) {
        const panelAppItems = locusList.items?.reduce(panelAppLocusListReducer, {})
        onChange({ locusListGuid, panelAppItems, locusList })
      } else {
        const { rawItems } = locusList
        onChange({ locusListGuid, rawItems, selectedMOIs })
      }
    }
  }

  handleDropdown = (locusListGuid) => {
    const { onChange } = this.props
    onChange({ locusListGuid, selectedMOIs: [] })
  }

  handleMOIselect = (selectedMOIs) => {
    const { locusList, onChange } = this.props
    onChange({ locusListGuid: locusList.locusListGuid, selectedMOIs })
  }

  moiOptions = () => {
    const { locusList } = this.props
    if (!locusList.items) {
      return []
    }

    const initials = locusList.items?.reduce((acc, gene) => {
      moiToMoiInitials(gene.pagene?.modeOfInheritance).forEach((initial) => {
        acc[initial] = true
      })
      if (moiToMoiInitials(gene.pagene?.modeOfInheritance).length === 0) {
        acc.other = true
      }
      return acc
    }, {}) || {}

    return PANEL_APP_MOI_OPTIONS.map(moi => ({
      ...moi,
      disabled: !initials[moi.value],
    }))
  }

  render() {
    const { locusList, projectLocusListOptions, selectedMOIs } = this.props
    const locusListGuid = locusList.locusListGuid || ''

    const GeneListDropdown = (
      <Dropdown
        inline
        selection
        search
        label="Gene List"
        value={locusListGuid}
        onChange={this.handleDropdown}
        options={projectLocusListOptions}
      />
    )

    const rightJustify = {
      justifyContent: 'right',
    }

    if (locusList.paLocusList) {
      return (
        <div className="inline fields" style={rightJustify}>
          <Multiselect
            className="wide eight"
            label="Modes of Inheritance"
            value={selectedMOIs}
            onChange={this.handleMOIselect}
            placeholder="Showing All MOIs"
            options={this.moiOptions()}
            color="violet"
          />
          { GeneListDropdown }
        </div>
      )
    }

    return (
      <div>
        { GeneListDropdown }
      </div>
    )
  }

}

const mapStateToProps = (state, ownProps) => ({
  projectLocusListOptions: getSearchedProjectsLocusListOptions(state, ownProps),
})

const LocusListDropdown = connect(mapStateToProps)(BaseLocusListDropdown)

const SUBSCRIPTION = { values: true }

const LocusListSelector = React.memo(({ value, ...props }) => (
  <LocusListItemsLoader locusListGuid={value.locusListGuid} reloadOnIdUpdate content hideLoading>
    <LocusListDropdown selectedMOIs={value.selectedMOIs} {...props} />
  </LocusListItemsLoader>
))

LocusListSelector.propTypes = {
  value: PropTypes.object,
}

export default props => (
  <FormSpy subscription={SUBSCRIPTION}>
    {({ values }) => <LocusListSelector {...props} projectFamilies={values.projectFamilies} />}
  </FormSpy>
)
