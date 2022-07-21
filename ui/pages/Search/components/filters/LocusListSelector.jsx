import PropTypes from 'prop-types'
import React from 'react'
import { connect } from 'react-redux'
import { FormSpy } from 'react-final-form'
import { Dropdown } from 'shared/components/form/Inputs'
import { LocusListItemsLoader } from 'shared/components/LocusListLoader'
import { formatPanelAppItems } from 'shared/utils/panelAppUtils'
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
        const panelAppItems = formatPanelAppItems(locusList.items)
        onChange({ locusListGuid, panelAppItems })
      } else {
        const { rawItems } = locusList
        onChange({ locusListGuid, rawItems, selectedMOIs })
      }
    }
  }

  onChange = (locusListGuid) => {
    const { onChange } = this.props
    onChange({ locusListGuid })
  }

  render() {
    const { locusList, projectLocusListOptions } = this.props
    const locusListGuid = locusList.locusListGuid || ''
    return (
      <div>
        <Dropdown
          inline
          selection
          search
          label="Gene List"
          value={locusListGuid}
          onChange={this.onChange}
          options={projectLocusListOptions}
        />
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
