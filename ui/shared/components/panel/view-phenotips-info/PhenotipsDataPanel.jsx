/* eslint-disable no-unused-expressions */
/* eslint-disable react/no-array-index-key */

import React from 'react'
import PropTypes from 'prop-types'
import { Label } from 'semantic-ui-react'

import { HorizontalSpacer, VerticalSpacer } from 'shared/components/Spacers'

import ShowPhenotipsModalButton from 'shared/components/buttons/ShowPhenotipsModalButton'
import { getNameForCategoryHpoId } from 'shared/utils/hpoUtils'

const infoDivStyle = {
  padding: '5px 0px 10px 20px',
}

export const hasPhenotipsDetails = phenotipsData =>
  phenotipsData && (phenotipsData.features || phenotipsData.rejectedGenes || phenotipsData.genes)

const PhenotipsSection = ({ phenotipsData, field, parseFieldRows, formatFieldRow, title, join, color }) => {
  let fieldData = phenotipsData[field]
  if (fieldData && parseFieldRows) {
    fieldData = parseFieldRows(fieldData)
  }
  if (!fieldData || fieldData.length < 1) {
    return null
  }
  return (
    <div>
      <Label basic horizontal color={color || 'grey'} content={title} />
      <div style={infoDivStyle}>
        {
          join ? fieldData.map(row => formatFieldRow(row)).join(join) : fieldData.map((row, i) => {
            return <div key={i}>{formatFieldRow(row)}</div>
          })
        }
      </div>
    </div>
  )
}

PhenotipsSection.propTypes = {
  phenotipsData: PropTypes.object,
  field: PropTypes.string,
  parseFieldRows: PropTypes.func,
  formatFieldRow: PropTypes.func,
  title: PropTypes.string,
  join: PropTypes.string,
  color: PropTypes.string,
}


const getHpoTermsForCategory = observed => (features) => {
  const hpoTermsByCategory = features.filter(
    hpoTerm => hpoTerm.observed === observed,
  ).reduce((acc, hpoTerm) => {
    if (!acc[hpoTerm.category]) {
      acc[hpoTerm.category] = [] //init array of features
    }

    acc[hpoTerm.category].push(hpoTerm)
    return acc
  }, {})

  return Object.entries(hpoTermsByCategory).map(
    ([categoryHpoId, terms]) => ({ categoryName: getNameForCategoryHpoId(categoryHpoId), terms }),
  ).sort(
    (a, b) => a.categoryName.localeCompare(b.categoryName),
  )
}

const formatHpoCategoryRow = category =>
  <div>
    <b>{category.categoryName}</b>: {
      (category.terms || []).map(
        hpoTerm => (hpoTerm.notes ? `${hpoTerm.label} (${hpoTerm.notes})` : hpoTerm.label),
      ).join(', ')
    }
  </div>

const formatGene = gene => `${gene.gene} ${gene.comments ? `(${gene.comments.trim()})` : ''}`

const PHENOTIPS_SECTIONS = [
  {
    field: 'features',
    title: 'Present',
    color: 'green',
    parseFieldRows: getHpoTermsForCategory('yes'),
    formatFieldRow: formatHpoCategoryRow,
  },
  {
    field: 'features',
    title: 'Not Present',
    color: 'red',
    parseFieldRows: getHpoTermsForCategory('no'),
    formatFieldRow: formatHpoCategoryRow,
  },
  {
    field: 'rejectedGenes',
    title: 'Previously Tested Genes',
    formatFieldRow: formatGene,
  },
  {
    field: 'genes',
    title: 'Candidate Genes',
    formatFieldRow: formatGene,
  },
  {
    field: 'ethnicity',
    title: 'Ancestry',
    parseFieldRows: (ethnicity) => {
      const parentalAncestries = []
      if (ethnicity.paternal_ethnicity && ethnicity.paternal_ethnicity.length) {
        parentalAncestries.push({ parent: 'father', ancestries: ethnicity.paternal_ethnicity })
      }
      if (ethnicity.maternal_ethnicity && ethnicity.maternal_ethnicity.length) {
        parentalAncestries.push({ parent: 'mother', ancestries: ethnicity.maternal_ethnicity })
      }
      return parentalAncestries
    },
    formatFieldRow: ({ parent, ancestries }) => `${parent} is ${ancestries.join(' / ')}`,
    join: ', ',
  },
  {
    field: 'global_age_of_onset',
    title: 'Age of Onset',
    formatFieldRow: s => s.label,
    join: ', ',
  },
]

class PhenotipsDataPanel extends React.Component
{
  static propTypes = {
    individual: PropTypes.object.isRequired,
    showDetails: PropTypes.bool.isRequired,
    showEditPhenotipsLink: PropTypes.bool.isRequired,
    showViewPhenotipsLink: PropTypes.bool,
  }

  render() {
    const { individual, showDetails, showEditPhenotipsLink, showViewPhenotipsLink = true } = this.props
    const { phenotipsData } = individual

    return (
      <div>
        <b>PhenoTips{(showDetails && hasPhenotipsDetails(phenotipsData)) ? ':' : ''}</b><HorizontalSpacer width={15} />
        { showViewPhenotipsLink && <ShowPhenotipsModalButton individual={individual} isViewOnly /> }
        {
          showEditPhenotipsLink && [
            <HorizontalSpacer key={1} width={10} />,
            <ShowPhenotipsModalButton key={2} individual={individual} isViewOnly={false} />,
          ]
        }
        {showDetails ?
          <div style={infoDivStyle}>
            {phenotipsData && hasPhenotipsDetails(phenotipsData) &&
              <div>
                <VerticalSpacer height={10} />
                {PHENOTIPS_SECTIONS.map(sectionProps =>
                  <PhenotipsSection
                    key={sectionProps.title}
                    phenotipsData={phenotipsData}
                    {...sectionProps}
                  />,
                )}
              </div>
            }
          </div> :
          <div style={{ display: 'inline-block', paddingBottom: '15px', color: 'gray' }}>
            <HorizontalSpacer width={30} />
            {(phenotipsData && phenotipsData.features) ? `${phenotipsData.features.length} phenotype terms` : null} &nbsp;
            {(phenotipsData && phenotipsData.rejectedGenes) ? `${phenotipsData.rejectedGenes.length} previously tested genes` : null} &nbsp;
            {(phenotipsData && phenotipsData.genes) ? `${phenotipsData.genes.length} candidate genes` : null}
          </div>
        }
      </div>)
  }
}

export { PhenotipsDataPanel as PhenotipsDataPanelComponent }

export default PhenotipsDataPanel

//const mapDispatchToProps = dispatch => bindActionCreators({ showPhenotipsModal }, dispatch)
//export default connect(null, mapDispatchToProps)(PhenotipsDataPanel)
