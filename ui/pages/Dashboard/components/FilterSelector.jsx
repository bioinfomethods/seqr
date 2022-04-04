import React from 'react'
import PropTypes from 'prop-types'
import styled from 'styled-components'
import { connect } from 'react-redux'
import { Form } from 'semantic-ui-react'

import { getProjectCategoriesByGuid } from 'redux/selectors'
import { updateFilter } from '../reducers'
import { getProjectFilter } from '../selectors'
import {
  SHOW_ALL,
} from '../constants'

const FilterContainer = styled.span`
  display: inline-block;
  min-width: 14em;
  font-size: 12px;

  div.visible.menu.transition {
    display: table !important;
    border-top: solid 0.5px #96c8da !important;
  }
`

const FilterSelector = React.memo(({ filter, options, onChange }) => (
  <FilterContainer>
    <Form.Select
      fluid
      name="filterSelector"
      value={filter}
      onChange={onChange}
      options={options}
    />
  </FilterContainer>
))

export { FilterSelector as FilterSelectorComponent }

FilterSelector.propTypes = {
  filter: PropTypes.string.isRequired,
  options: PropTypes.arrayOf(PropTypes.obect),
  onChange: PropTypes.func.isRequired,
}

const mapStateToProps = state => ({
  filter: getProjectFilter(state),
  options: [
    { value: SHOW_ALL, text: 'All project categories', key: SHOW_ALL },
    ...Object.values(getProjectCategoriesByGuid(state)).map(
      projectCategory => ({ value: projectCategory.guid, text: projectCategory.name, key: projectCategory.guid }),
    ),
  ],
})

const mapDispatchToProps = { onChange: (event, data) => updateFilter(data.value) }

export default connect(mapStateToProps, mapDispatchToProps)(FilterSelector)
